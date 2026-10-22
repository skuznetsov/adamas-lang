#!/usr/bin/env python3
"""Compare adjacent unary arguments and spaced binary operators after super."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(os.environ.get("ADAMAS_ROOT", str(Path(__file__).resolve().parent.parent)))
FIXTURES = Path(__file__).resolve().parent / "super_operator_spacing"
SAFE = Path(os.environ.get("ADAMAS_RUN_SAFE", str(ROOT / "scripts/run_safe.sh")))
ORIGINAL_NAME = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
ORIGINAL = Path(shutil.which(ORIGINAL_NAME) or ORIGINAL_NAME).resolve()
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n")
CASE = "operator_whitespace_boundary"


def footer(raw, expected):
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing safe-run records"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1
    exit_match, resource_match = EXIT.fullmatch(lines[-2]), RESOURCE.fullmatch(lines[-1])
    assert exit_match and resource_match, "malformed safe-run records"
    assert int(exit_match[1]) == expected and int(resource_match[1]) == expected
    return lines[-2] + lines[-1]


def stage(label, compiler, work):
    binary = work / (label + ".program")
    cache = work / (label + ".cache")
    cache.mkdir()
    env = {**os.environ, "CRYSTAL_CACHE_DIR": str(cache), "ADAMAS_LLVM_CACHE": "0"}
    source = str(FIXTURES / (CASE + ".cr"))
    if label == "original":
        args = ["build", "--no-debug", "--prelude=empty"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        args += [source, "-o", str(binary)]
    else:
        args = [source, "--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache", "-o", str(binary)]
    result = subprocess.run([str(SAFE), str(compiler), "120", "4096", *args], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145)
    (work / (label + ".compile.log")).write_bytes(result.stdout)
    assert result.returncode == 0 and binary.is_file(), f"{label} compile failed: {result.stdout!r}"
    footer(result.stdout, 0)
    run = subprocess.run([str(SAFE), str(binary), "5", "512"],
                         env={**env, "RUN_SAFE_PASSTHROUGH_STDIO": "1"},
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    (work / (label + ".stdout")).write_bytes(run.stdout)
    (work / (label + ".stderr")).write_bytes(run.stderr)
    assert run.returncode == 0, f"{label} runtime status: {run.returncode}"
    assert run.stderr == footer(run.stderr, 0), f"{label} runtime stderr: {run.stderr!r}"
    expected = (FIXTURES / (CASE + ".expected")).read_bytes()
    assert run.stdout == expected, f"{label} stdout: {run.stdout!r}, expected {expected!r}"
    print(f"PASS[{label}:super_operator_spacing] stdout={run.stdout!r}", flush=True)


def main():
    assert len(sys.argv) <= 2, "usage: super_operator_spacing_repro.sh [candidate-adamas]"
    candidate = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT / "bin/adamas"
    assert all(path.is_file() and os.access(path, os.X_OK) for path in (SAFE, ORIGINAL, candidate))
    output = os.environ.get("SUPER_OPERATOR_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists()
        work.mkdir()
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_super_operator_spacing_"))
    passed = False
    try:
        stage("original", ORIGINAL, work)
        print("ORIGINAL_PASS_COMPLETE[super_operator_spacing]", flush=True)
        stage("candidate", candidate, work)
        passed = True
    finally:
        for path in work.glob("*.program*"):
            path.unlink()
        for path in work.glob("*.cache"):
            shutil.rmtree(path)
        if passed and not output:
            shutil.rmtree(work)
        else:
            print("kept_logs=" + str(work), file=sys.stderr)


if __name__ == "__main__":
    main()
