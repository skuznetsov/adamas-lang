#!/usr/bin/env python3
"""Original-first no-prelude runtime oracle for capture-owner shapes."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

def find_repo_root() -> Path:
    if os.environ.get("ADAMAS_ROOT"):
        return Path(os.environ["ADAMAS_ROOT"]).resolve()
    for parent in Path(__file__).resolve().parents:
        if (parent / "scripts/run_safe.sh").is_file():
            return parent
    raise RuntimeError("set ADAMAS_ROOT to the Adamas checkout")


PACKET = Path(__file__).resolve().parent
FIXTURES = PACKET / "fixtures"
CASES = [
    "branch_callback_write",
    "nested_callback_write",
    "call_valued_initial_binding",
    "parenthesized_call_initial_binding",
    "copied_call_initial_binding",
    "conditional_call_initial_binding",
    "method_parameter_capture_write",
    "ordinary_block_parameter_shadow",
    "multiline_main_owner_capture",
]
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n")


def footer(raw: bytes, expected: int) -> bytes:
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing safe-run records"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1
    exit_match, resource_match = EXIT.fullmatch(lines[-2]), RESOURCE.fullmatch(lines[-1])
    assert exit_match and resource_match, "malformed safe-run records"
    assert int(exit_match[1]) == expected and int(resource_match[1]) == expected
    return lines[-2] + lines[-1]


def self_test() -> None:
    footer(b"compiler output\n[EXIT: 0] after ~0.2s\n[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=0 wall_s=0.2\n", 0)
    for malformed in (
        b"[EXIT: 0] after ~0.1s\n",
        b"[EXIT: 0] after ~0.1s\n[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=1 wall_s=0.1\n",
        b"[EXIT: 0] after ~0.1s\n[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=signal reason=signal exit_code=0 wall_s=0.1\n",
    ):
        try:
            footer(malformed, 0)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"accepted malformed footer: {malformed!r}")
    for name in CASES:
        assert (FIXTURES / f"{name}.cr").is_file(), name
        assert (FIXTURES / f"{name}.expected").read_bytes() in (b"A", b"B"), name
    assert len(set(CASES)) == len(CASES)
    manifest = json.loads((PACKET / "packet_manifest.json").read_text())
    assert set(manifest["positives"]) == set(CASES)
    assert "annotation" not in (PACKET / "packet_manifest.json").read_text().lower()
    print("PASS static runner/fixture/footer self-test; no compiler invoked", flush=True)


def case_run(label: str, compiler: Path, case: str, safe: Path, work: Path) -> None:
    source = FIXTURES / f"{case}.cr"
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
        args = [str(source), "--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache", "-o", str(binary)]
    compiled = subprocess.run(
        [str(safe), str(compiler), "120", "4096", *args],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145,
    )
    (work / f"{label}.{case}.compile.log").write_bytes(compiled.stdout)
    footer(compiled.stdout, 0)
    assert compiled.returncode == 0, f"{label}:{case} compile status {compiled.returncode}: {compiled.stdout!r}"
    assert binary.is_file(), f"{label}:{case} missing executable"
    result = subprocess.run(
        [str(safe), str(binary), "5", "512"],
        env={**env, "RUN_SAFE_PASSTHROUGH_STDIO": "1"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
    )
    (work / f"{label}.{case}.stdout").write_bytes(result.stdout)
    (work / f"{label}.{case}.stderr").write_bytes(result.stderr)
    assert result.returncode == 0, f"{label}:{case} runtime status {result.returncode}"
    assert result.stderr == footer(result.stderr, 0), f"{label}:{case} malformed runtime footer"
    expected = (FIXTURES / f"{case}.expected").read_bytes()
    assert result.stdout == expected, f"{label}:{case} stdout={result.stdout!r}, expected={expected!r}"
    print(f"PASS[{label}:{case}] stdout={result.stdout!r}", flush=True)


def main() -> None:
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    assert len(sys.argv) == 2, "usage: capture_owner_shape_repro.py /absolute/path/to/adamas"
    adamas_root = find_repo_root()
    safe = Path(os.environ.get("ADAMAS_RUN_SAFE", str(adamas_root / "scripts/run_safe.sh"))).resolve()
    original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
    original = Path(shutil.which(original_name) or original_name).resolve()
    candidate = Path(sys.argv[1]).resolve()
    assert all(path.is_file() and os.access(path, os.X_OK) for path in (safe, original, candidate))
    output = os.environ.get("CAPTURE_OWNER_SHAPE_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists()
        work.mkdir(parents=True)
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_capture_owner_shape_"))
    passed = False
    try:
        for label, compiler in (("original", original), ("candidate", candidate)):
            failures = []
            for case in CASES:
                try:
                    case_run(label, compiler, case, safe, work)
                except Exception as exc:
                    failures.append((case, str(exc)))
                    print(f"FAIL[{label}:{case}] {exc}", flush=True)
            assert not failures, f"{label} failures: {failures}"
            print(f"{label.upper()}_PASS_COMPLETE[capture_owner_shapes]", flush=True)
        passed = True
    finally:
        for path in work.glob("*.program"):
            path.unlink()
        for path in work.glob("*.cache"):
            shutil.rmtree(path)
        if passed and not output:
            shutil.rmtree(work)
        else:
            print("kept_logs=" + str(work), file=sys.stderr)


if __name__ == "__main__":
    main()
