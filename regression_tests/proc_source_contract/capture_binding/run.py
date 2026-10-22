#!/usr/bin/env python3
"""Serial original-first no-prelude oracle for Proc.new unpack capture binding."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

PACKET = Path(__file__).resolve().parent
FIXTURES = PACKET / "fixtures"
CASE_NAMES = (
    "proc_new_flat_collisions",
    "proc_new_nested_collisions",
    "proc_literal_parameter_shadow",
    "ordinary_block_unpack_shadow",
)
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(
    rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit "
    rb"reason=exit exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n"
)


def find_root() -> Path:
    configured = os.environ.get("ADAMAS_ROOT")
    if configured:
        root = Path(configured).resolve()
        assert (root / "scripts/run_safe.sh").is_file(), root
        return root
    for parent in PACKET.parents:
        if (parent / "scripts/run_safe.sh").is_file():
            return parent
        sibling = parent / "adamas"
        if (sibling / "scripts/run_safe.sh").is_file():
            return sibling
    raise RuntimeError("set ADAMAS_ROOT to the Adamas checkout")


def footer(raw: bytes, expected: int) -> bytes:
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing safe-run footer"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1
    exit_match, resource_match = EXIT.fullmatch(lines[-2]), RESOURCE.fullmatch(lines[-1])
    assert exit_match and resource_match, "malformed safe-run footer"
    assert int(exit_match[1]) == expected and int(resource_match[1]) == expected
    return lines[-2] + lines[-1]


def self_test() -> None:
    manifest = json.loads((PACKET / "manifest.json").read_text(encoding="utf-8"))
    for relative, expected_hash in manifest["files"].items():
        observed_hash = hashlib.sha256((PACKET / relative).read_bytes()).hexdigest()
        assert observed_hash == expected_hash, f"packet file hash mismatch: {relative}"
    sums = (PACKET / "SHA256SUMS").read_bytes()
    sums_hash = hashlib.sha256(sums).hexdigest()
    assert (PACKET / "SHA256SUMS.sha256").read_text().split()[0] == sums_hash
    expected_bytes = {
        "proc_new_flat_collisions": b"ABABB !\n",
        "proc_new_nested_collisions": b"ABABL !\n",
        "proc_literal_parameter_shadow": b"AA!A\n",
        "ordinary_block_unpack_shadow": b"ABBAB\n",
    }
    assert tuple(expected_bytes) == CASE_NAMES
    for case, expected in expected_bytes.items():
        assert (FIXTURES / (case + ".cr")).is_file(), case
        assert (FIXTURES / (case + ".expected")).read_bytes() == expected, case
    good = (
        b"[EXIT: 0] after ~0.01s\n"
        b"[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit "
        b"reason=exit exit_code=0 elapsed_ms=1 peak_rss_bytes=2\n"
    )
    assert footer(good, 0) == good
    assert footer(b"safe-run prelude\n" + good, 0) == good
    for bad in (
        good[:-1],
        good.replace(b"exit_code=0", b"exit_code=1"),
        b"[EXIT: 0] after ~0.01s\n",
    ):
        try:
            footer(bad, 0)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"accepted malformed footer: {bad!r}")
    print("PASS static packet and footer self-tests")


def compile_and_run(label: str, compiler: Path, case: str, safe: Path, work: Path) -> None:
    source = FIXTURES / (case + ".cr")
    expected = (FIXTURES / (case + ".expected")).read_bytes()
    binary = work / f"{label}.{case}.program"
    cache = work / f"{label}.{case}.cache"
    cache.mkdir()
    env = {**os.environ, "CRYSTAL_CACHE_DIR": str(cache), "ADAMAS_LLVM_CACHE": "0"}
    if label == "original":
        args = ["build", "--no-debug", "--prelude=empty"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        args += [str(source), "-o", str(binary)]
    else:
        args = [
            str(source), "--no-prelude", "--no-debug", "--no-ast-cache",
            "--no-llvm-cache", "-o", str(binary),
        ]
    compiled = subprocess.run(
        [str(safe), str(compiler), "120", "4096", *args],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145,
    )
    (work / f"{label}.{case}.compile.log").write_bytes(compiled.stdout)
    assert compiled.returncode == 0, (
        f"{label}:{case} compile rc={compiled.returncode}: {compiled.stdout!r}"
    )
    footer(compiled.stdout, 0)
    assert binary.is_file(), f"{label}:{case} produced no executable"
    runtime = subprocess.run(
        [str(safe), str(binary), "5", "512"],
        env={**env, "RUN_SAFE_PASSTHROUGH_STDIO": "1"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
    )
    (work / f"{label}.{case}.stdout").write_bytes(runtime.stdout)
    (work / f"{label}.{case}.stderr").write_bytes(runtime.stderr)
    assert runtime.returncode == 0, f"{label}:{case} runtime rc={runtime.returncode}"
    assert runtime.stderr == footer(runtime.stderr, 0), runtime.stderr
    assert runtime.stdout == expected, (
        f"{label}:{case} stdout={runtime.stdout!r}; expected={expected!r}"
    )
    print(f"PASS[{label}:{case}] stdout={runtime.stdout!r}", flush=True)


def main() -> None:
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    assert len(sys.argv) <= 2, "usage: run.py [candidate-adamas]"
    root = find_root()
    safe = Path(os.environ.get("ADAMAS_RUN_SAFE", str(root / "scripts/run_safe.sh"))).resolve()
    original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
    original = Path(shutil.which(original_name) or original_name).resolve()
    candidate = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else root / "bin/adamas"
    assert all(p.is_file() and os.access(p, os.X_OK) for p in (safe, original, candidate))

    output = os.environ.get("PROC_UNPACK_SHADOW_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists(), work
        work.mkdir(parents=True)
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_proc_unpack_shadow_"))

    passed = False
    try:
        # This barrier is intentional: no candidate compiler invocation occurs
        # unless all pinned originals match the explicit expected byte streams.
        for label, compiler in (("original", original), ("candidate", candidate)):
            for case in CASE_NAMES:
                compile_and_run(label, compiler, case, safe, work)
            print(f"{label.upper()}_PASS_COMPLETE[proc_unpack_shadow]", flush=True)
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
