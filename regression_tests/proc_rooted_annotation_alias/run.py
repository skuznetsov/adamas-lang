#!/usr/bin/env python3
"""Original-first discriminator for absolute aliases in Proc annotations.

The harness never invokes a compiler or generated program except through
scripts/run_safe.sh. --self-test is static and does not locate compilers.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures"
POSITIVE = (
    "rooted_alias_annotation",
    "inverse_width_root_int64_positive",
    "nested_lexical_rooted_alias_positive",
)
NEGATIVE = (
    "root_int32_rejects_lexical_int64",
    "inverse_root_int64_rejects_lexical_int32",
    "nested_lexical_rooted_alias_rejects_inner_int64",
)
EXIT_LINE = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE_LINE = re.compile(rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n")
BAD_DIAGNOSTIC = (b"Parse error", b"SIGSEGV", b"stack overflow", b"Segmentation fault", b"internal compiler error", b"LLVM ERROR", b"Bus error", b"unhandled exception")


def find_root():
    configured = os.environ.get("ADAMAS_ROOT")
    if configured:
        root = Path(configured).resolve()
        if (root / "scripts/run_safe.sh").is_file():
            return root
        raise RuntimeError(f"ADAMAS_ROOT lacks scripts/run_safe.sh: {root}")
    for parent in HERE.parents:
        if (parent / "scripts/run_safe.sh").is_file():
            return parent
        sibling = parent / "adamas"
        if (sibling / "scripts/run_safe.sh").is_file():
            return sibling
    raise RuntimeError("set ADAMAS_ROOT to the Adamas checkout")


def footer(raw: bytes, expected: int) -> bytes:
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing safe-run records"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1
    exit_match = EXIT_LINE.fullmatch(lines[-2])
    resource_match = RESOURCE_LINE.fullmatch(lines[-1])
    assert exit_match and resource_match, "malformed safe-run footer"
    assert int(exit_match[1]) == expected and int(resource_match[1]) == expected
    return lines[-2] + lines[-1]


def semantic_rejection(case: str, output: bytes) -> bool:
    required = (FIXTURES / (case + ".reject")).read_bytes().splitlines()
    return (all(marker in output for marker in required) and
            not any(marker.lower() in output.lower() for marker in BAD_DIAGNOSTIC))


def self_test():
    assert len(POSITIVE) == 3 and len(NEGATIVE) == 3
    assert all((FIXTURES / (case + ".cr")).is_file() for case in POSITIVE + NEGATIVE)
    assert all((FIXTURES / (case + ".expected")).is_file() for case in POSITIVE)
    assert all((FIXTURES / (case + ".reject")).is_file() for case in NEGATIVE)
    for case in NEGATIVE:
        expected = (FIXTURES / (case + ".reject")).read_bytes().splitlines()
        synthetic = b"error: " + b"; ".join(expected) + b"\n"
        assert semantic_rejection(case, synthetic)
        assert not semantic_rejection(case, b"error: unrelated semantic error\n")
        assert not semantic_rejection(case, synthetic + b"Parse error\n")
        assert not semantic_rejection(case, b"SIGSEGV\n" + synthetic)
    good = (b"[EXIT: 0] after ~0.01s\n"
            b"[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=0 elapsed_ms=1 peak_rss_bytes=2\n")
    assert footer(good, 0) == good
    assert not all((FIXTURES / (case + ".cr")).is_file() for case in POSITIVE + NEGATIVE + ("missing_case",))
    print("PASS static packet checks (no compiler invoked)")


def compile_case(label: str, compiler: Path, case: str, work: Path, root: Path, positive: bool):
    source = FIXTURES / (case + ".cr")
    binary = work / f"{label}.{case}.program"
    cache = work / f"{label}.{case}.cache"
    cache.mkdir()
    env = {**os.environ, "CRYSTAL_CACHE_DIR": str(cache), "ADAMAS_LLVM_CACHE": "0"}
    safe = Path(os.environ.get("ADAMAS_RUN_SAFE", str(root / "scripts/run_safe.sh"))).resolve()
    assert safe.is_file() and os.access(safe, os.X_OK)
    if label == "original":
        args = [str(safe), str(compiler), "120", "4096", "build", "--prelude=empty", "--no-debug"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        args += [str(source), "-o", str(binary)]
    else:
        args = [str(safe), str(compiler), "120", "4096", str(source), "--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache", "-o", str(binary)]
    result = subprocess.run(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145)
    (work / f"{label}.{case}.compile.log").write_bytes(result.stdout)
    expected_status = 0 if positive else 1
    assert result.returncode == expected_status, f"{label}:{case} compiler rc={result.returncode}: {result.stdout!r}"
    footer(result.stdout, expected_status)
    if not positive:
        assert not binary.exists(), f"rejected fixture produced executable: {case}"
        assert semantic_rejection(case, result.stdout), f"{label}:{case} missing semantic rejection markers: {result.stdout!r}"
        print(f"PASS[{label}:{case}] semantic rejection", flush=True)
        return
    assert binary.is_file(), f"missing executable: {case}"
    runtime = subprocess.run(
        [str(safe), str(binary), "5", "512"],
        env={**env, "RUN_SAFE_PASSTHROUGH_STDIO": "1"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
    )
    (work / f"{label}.{case}.stdout").write_bytes(runtime.stdout)
    (work / f"{label}.{case}.stderr").write_bytes(runtime.stderr)
    assert runtime.returncode == 0, f"{label}:{case} runtime rc={runtime.returncode}: {runtime.stderr!r}"
    assert runtime.stderr == footer(runtime.stderr, 0), f"{label}:{case} unexpected runtime stderr {runtime.stderr!r}"
    expected = (FIXTURES / (case + ".expected")).read_bytes()
    assert runtime.stdout == expected, f"{label}:{case} stdout={runtime.stdout!r}; expected={expected!r}"
    print(f"PASS[{label}:{case}] stdout={runtime.stdout!r}", flush=True)


def run_stage(label: str, compiler: Path, work: Path, root: Path):
    failures = []
    for positive, cases in ((True, POSITIVE), (False, NEGATIVE)):
        for case in cases:
            try:
                compile_case(label, compiler, case, work, root, positive)
            except Exception as exc:
                failures.append((case, str(exc)))
                print(f"FAIL[{label}:{case}] {exc}", flush=True)
    return failures


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    assert len(sys.argv) == 2, "usage: run.py candidate-adamas"
    root = find_root()
    safe = Path(os.environ.get("ADAMAS_RUN_SAFE", str(root / "scripts/run_safe.sh"))).resolve()
    original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
    original = Path(shutil.which(original_name) or original_name).resolve()
    candidate = Path(sys.argv[1]).resolve()
    assert all(path.is_file() and os.access(path, os.X_OK) for path in (safe, original, candidate))
    explicit_output = os.environ.get("PROC_ROOT_ALIAS_OUTPUT_DIR")
    if explicit_output:
        work = Path(explicit_output)
        assert work.is_absolute() and not work.exists()
        work.mkdir(parents=True)
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_proc_rooted_alias_"))
    success = False
    try:
        original_failures = run_stage("original", original, work, root)
        if original_failures:
            raise AssertionError(f"original-first qualification failed; candidate skipped: {original_failures}")
        print("ORIGINAL_PASS_COMPLETE[proc_rooted_alias]", flush=True)
        candidate_failures = run_stage("candidate", candidate, work, root)
        if candidate_failures:
            raise AssertionError(f"candidate failures: {candidate_failures}")
        print("CANDIDATE_PASS_COMPLETE[proc_rooted_alias]", flush=True)
        success = True
    finally:
        for path in work.glob("*.program*"):
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
        for path in work.glob("*.cache"):
            shutil.rmtree(path, ignore_errors=True)
        if success and not explicit_output:
            shutil.rmtree(work)
        else:
            print("kept_logs=" + str(work), file=sys.stderr)


if __name__ == "__main__":
    main()
