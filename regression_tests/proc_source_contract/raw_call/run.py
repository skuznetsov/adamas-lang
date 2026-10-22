#!/usr/bin/env python3
"""Original-first nonempty raw-callback source-callshape regression."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile


def find_root():
    configured = os.environ.get("ADAMAS_ROOT")
    if configured:
        root = Path(configured).resolve()
        if (root / "scripts/run_safe.sh").is_file():
            return root
        raise RuntimeError("ADAMAS_ROOT does not contain scripts/run_safe.sh")
    for parent in Path(__file__).resolve().parents:
        if (parent / "scripts/run_safe.sh").is_file():
            return parent
    raise RuntimeError("set ADAMAS_ROOT to the Adamas checkout")


ROOT = find_root()
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SAFE = Path(os.environ.get("ADAMAS_RUN_SAFE", str(ROOT / "scripts/run_safe.sh"))).resolve()
ORIGINAL_NAME = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
ORIGINAL = Path(shutil.which(ORIGINAL_NAME) or ORIGINAL_NAME).resolve()
EXPECTED = b"AB\n"
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n")


def footer(raw, expected):
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing run_safe records"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1, "missing or duplicate EXIT record"
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1, "missing or duplicate resource record"
    exit_match = EXIT.fullmatch(lines[-2])
    resource_match = RESOURCE.fullmatch(lines[-1])
    assert exit_match and resource_match, "malformed terminal run_safe records"
    assert int(exit_match.group(1)) == expected and int(resource_match.group(1)) == expected, "run_safe status mismatch"
    return lines[-2] + lines[-1]


def self_test():
    valid = b"AB\n[EXIT: 0] after ~0.01s\n[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=0 elapsed_ms=10 peak_rss_mb=12 peak_fds=4\n"
    assert footer(valid, 0) == valid.splitlines(keepends=True)[-2] + valid.splitlines(keepends=True)[-1]
    for bad in (
        valid + b"noise\n",
        b"AB\n[EXIT: 1] after ~0.01s\n[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=0 elapsed_ms=10\n",
        b"AB\n[EXIT: 0] after ~0.01s\n[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=timeout reason=timeout exit_code=124 elapsed_ms=10\n",
    ):
        try:
            footer(bad, 0)
        except AssertionError:
            pass
        else:
            raise AssertionError("footer self-test accepted invalid terminal records")
    assert EXPECTED == b"AB\n"
    print("PASS static footer/stdout self-test")


def compile_and_run(label, compiler, source, work):
    binary = work / (label + ".program")
    cache = work / (label + ".cache")
    cache.mkdir()
    env = {**os.environ, "CRYSTAL_CACHE_DIR": str(cache), "ADAMAS_LLVM_CACHE": "0"}
    if label == "original":
        args = ["build", "--no-debug", "--prelude=empty"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
    else:
        args = ["--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache"]
    args.extend([str(source), "-o", str(binary)])
    compiled = subprocess.run([str(SAFE), str(compiler), "180", "4096", *args], env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=210)
    (work / (label + ".compile.log")).write_bytes(compiled.stdout)
    assert compiled.returncode == 0, f"{label} compile failed: {compiled.stdout!r}"
    footer(compiled.stdout, 0)
    assert binary.is_file(), f"{label} compiler returned success without executable"
    runtime = subprocess.run([str(SAFE), str(binary), "5", "512"],
                             env={**env, "RUN_SAFE_PASSTHROUGH_STDIO": "1"},
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    (work / (label + ".stdout")).write_bytes(runtime.stdout)
    (work / (label + ".stderr")).write_bytes(runtime.stderr)
    assert runtime.returncode == 0, f"{label} runtime status {runtime.returncode}"
    assert runtime.stderr == footer(runtime.stderr, 0), f"unexpected runtime stderr: {runtime.stderr!r}"
    assert runtime.stdout == EXPECTED, f"{label} stdout {runtime.stdout!r}, expected {EXPECTED!r}"
    print(f"PASS[{label}] stdout={runtime.stdout!r}", flush=True)


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    assert len(sys.argv) <= 2, "usage: raw_callback_callshape_repro.sh [candidate-adamas]"
    candidate = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT / "bin/adamas"
    assert SAFE.is_file() and os.access(SAFE, os.X_OK), f"missing safe runner: {SAFE}"
    assert ORIGINAL.is_file() and os.access(ORIGINAL, os.X_OK), f"missing original compiler: {ORIGINAL}"
    assert candidate.is_file() and os.access(candidate, os.X_OK), f"missing candidate compiler: {candidate}"
    source = FIXTURES / "raw_callback_callshape.cr"
    assert source.is_file() and (FIXTURES / "raw_callback_callsite_helper.cr").is_file()
    output = os.environ.get("RAW_CALLBACK_CALLSHAPE_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists()
        work.mkdir(parents=True)
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_raw_callback_callshape_"))
    passed = False
    try:
        # The candidate is not invoked until the pinned original has both
        # compiled and run with byte-exact output.
        compile_and_run("original", ORIGINAL, source, work)
        print("ORIGINAL_PASS_COMPLETE[raw_callback_callshape]", flush=True)
        compile_and_run("candidate", candidate, source, work)
        print("CANDIDATE_PASS_COMPLETE[raw_callback_callshape]", flush=True)
        passed = True
    finally:
        for binary in work.glob("*.program"):
            binary.unlink()
        for cache in work.glob("*.cache"):
            shutil.rmtree(cache)
        if passed and not output:
            shutil.rmtree(work)
        else:
            print("kept_logs=" + str(work), file=sys.stderr)


if __name__ == "__main__":
    main()
