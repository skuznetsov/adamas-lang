#!/usr/bin/env python3
"""Original-first Proc#call admission oracle. --self-test never invokes a compiler."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures"
POSITIVE = ('exact_int8_input', 'exact_int16_input', 'exact_int32_input', 'exact_int64_input', 'exact_float32_input', 'exact_float64_input')
NEGATIVE = ('reject_numeric_literal_int8_boundary', 'reject_numeric_negative_literal_int8_boundary', 'reject_numeric_integer_domain_widening', 'reject_numeric_float32_to_float64_expression', 'reject_numeric_int16_expression_to_float32', 'reject_numeric_int32_expression_to_float64', 'reject_int8_literal_overflow', 'reject_int8_int32_expression', 'reject_negative_int8_literal_underflow', 'reject_int32_expression_to_float32', 'reject_wrong_scalar', 'reject_missing_argument_member_access', 'reject_extra_argument_direct_call')
CASES = POSITIVE + NEGATIVE
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(
    rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit "
    rb"exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n"
)
BAD_REJECTION = (
    b"parse error", b"sigsegv", b"stack overflow", b"segmentation fault",
    b"failed to emit", b"could not emit", b"unable to emit", b"failed to write executable",
    b"llvm error", b"bus error", b"unhandled exception", b"compiler bug",
)


def find_root():
    configured = os.environ.get("ADAMAS_ROOT")
    if configured:
        root = Path(configured).resolve()
        assert (root / "scripts/run_safe.sh").is_file(), root
        return root
    for parent in HERE.parents:
        if (parent / "scripts/run_safe.sh").is_file():
            return parent
        sibling = parent / "adamas"
        if (sibling / "scripts/run_safe.sh").is_file():
            return sibling
    raise RuntimeError("set ADAMAS_ROOT to the Adamas checkout")


def footer(raw: bytes, expected: int) -> bytes:
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing run_safe footer"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1
    exit_match = EXIT.fullmatch(lines[-2])
    resource_match = RESOURCE.fullmatch(lines[-1])
    assert exit_match and resource_match, "malformed run_safe footer"
    assert int(exit_match[1]) == expected and int(resource_match[1]) == expected
    return lines[-2] + lines[-1]


def rejection_markers(label: str, case: str) -> tuple[bytes, ...]:
    path = FIXTURES / f"{case}.{label}.reject"
    markers = tuple(line.strip() for line in path.read_bytes().splitlines() if line.strip())
    assert markers, f"{path} has no semantic rejection markers"
    return markers


def check_rejection(label: str, case: str, raw: bytes):
    lowered = raw.lower()
    markers = rejection_markers(label, case)
    assert any(marker.lower() in lowered for marker in markers), (
        f"{case} missing semantic diagnostic alternatives {markers!r}: {raw!r}"
    )
    assert not any(marker in lowered for marker in BAD_REJECTION), raw
    assert b"error:" in lowered, raw


def self_test():
    sample_footer = (
        b"compile output\n[EXIT: 0] after ~0.01s\n"
        b"[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit "
        b"exit_code=0 elapsed_ms=10 max_rss_kb=100 fd_count=4\n"
    )
    assert footer(sample_footer, 0) == b"[EXIT: 0] after ~0.01s\n" + sample_footer.splitlines(keepends=True)[-1]
    assert len(CASES) == len(set(CASES))
    assert set(CASES) == {path.stem for path in FIXTURES.glob("*.cr")}
    assert {path.stem for path in FIXTURES.glob("*.expected")} == set(POSITIVE)
    for case in NEGATIVE:
        for label in ("original", "candidate"):
            markers = rejection_markers(label, case)
            for marker in markers:
                check_rejection(label, case, b"error: " + marker + b"\n")
                check_rejection(label, case, b"ERROR: " + marker + b"\n")
                for bad in BAD_REJECTION:
                    try:
                        check_rejection(label, case, b"error: " + marker + b"\n" + bad + b"\n")
                    except AssertionError:
                        pass
                    else:
                        raise AssertionError(f"accepted false-positive marker {bad!r}")
            try:
                check_rejection(label, case, b"error: unrelated undefined constant\n")
            except AssertionError:
                pass
            else:
                raise AssertionError(f"accepted unrelated error for {label}:{case}")
    print(f"PASS packet self-test: {len(POSITIVE)} positives, {len(NEGATIVE)} negatives; no compiler invoked")


def run_case(label: str, compiler: Path, case: str, work: Path, safe: Path):
    source = FIXTURES / (case + ".cr")
    binary = work / (label + "." + case + ".program")
    cache = work / (label + "." + case + ".cache")
    cache.mkdir()
    env = {**os.environ, "CRYSTAL_CACHE_DIR": str(cache), "ADAMAS_LLVM_CACHE": "0"}
    if label == "original":
        args = ["build", "--no-debug", "--prelude=empty"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        args += [str(source), "-o", str(binary)]
    else:
        args = [str(source), "--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache", "-o", str(binary)]
    result = subprocess.run(
        [str(safe), str(compiler), "120", "4096", *args], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145,
    )
    (work / (label + "." + case + ".compile.log")).write_bytes(result.stdout)
    positive = case in POSITIVE
    expected_status = 0 if positive else 1
    assert result.returncode == expected_status, (
        f"{label}:{case} compile rc={result.returncode}: {result.stdout!r}"
    )
    footer(result.stdout, expected_status)
    if not positive:
        assert not binary.exists(), f"{label}:{case} emitted an executable despite rejection"
        check_rejection(label, case, result.stdout)
        print(f"PASS[{label}:{case}] semantic rejection", flush=True)
        return
    assert binary.is_file(), f"{label}:{case} failed to emit executable"
    runtime = subprocess.run(
        [str(safe), str(binary), "5", "512"],
        env={**env, "RUN_SAFE_PASSTHROUGH_STDIO": "1"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
    )
    (work / (label + "." + case + ".stdout")).write_bytes(runtime.stdout)
    (work / (label + "." + case + ".stderr")).write_bytes(runtime.stderr)
    assert runtime.returncode == 0, f"{label}:{case} runtime rc={runtime.returncode}"
    assert runtime.stderr == footer(runtime.stderr, 0), runtime.stderr
    expected = (FIXTURES / (case + ".expected")).read_bytes()
    assert runtime.stdout == expected, f"{label}:{case} stdout={runtime.stdout!r}, expected={expected!r}"
    print(f"PASS[{label}:{case}] stdout={runtime.stdout!r}", flush=True)


def main():
    args = sys.argv[1:]
    if args == ["--self-test"]:
        self_test()
        return
    original_only = args == ["--original-only"]
    assert original_only or len(args) == 1, "usage: run.py --self-test | --original-only | candidate-adamas"
    root = find_root()
    safe = Path(os.environ.get("ADAMAS_RUN_SAFE", str(root / "scripts/run_safe.sh"))).resolve()
    original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
    original = Path(shutil.which(original_name) or original_name).resolve()
    candidate = None if original_only else Path(args[0]).resolve()
    assert safe.is_file() and os.access(safe, os.X_OK), safe
    assert original.is_file() and os.access(original, os.X_OK), original
    if candidate:
        assert candidate.is_file() and os.access(candidate, os.X_OK), candidate

    output = os.environ.get("PROC_CALL_ADMISSION_ORACLE_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists(), work
        work.mkdir()
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_proc_call_admission_oracle_"))
    try:
        # The candidate is considered only after every original control passes.
        for label, compiler in (("original", original), ("candidate", candidate)):
            if compiler is None:
                continue
            failures = []
            for case in CASES:
                try:
                    run_case(label, compiler, case, work, safe)
                except Exception as exc:
                    failures.append((case, str(exc)))
                    print(f"FAIL[{label}:{case}] {exc}", flush=True)
            assert not failures, f"{label} failures: {failures}"
            print(f"{label.upper()}_PASS_COMPLETE[proc_call_admission_oracle]", flush=True)
    finally:
        for binary in work.glob("*.program"):
            binary.unlink()
        for cache in work.glob("*.cache"):
            shutil.rmtree(cache)
        print("kept_logs=" + str(work), file=sys.stderr)


if __name__ == "__main__":
    main()
