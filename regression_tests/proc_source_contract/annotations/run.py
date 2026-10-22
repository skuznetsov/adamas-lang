#!/usr/bin/env python3
"""Original-first contract probe for explicit Proc literal result annotations."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures"

def find_root():
    configured = os.environ.get("ADAMAS_ROOT")
    if configured:
        root = Path(configured).resolve()
        assert (root / "scripts/run_safe.sh").is_file(), root
        return root
    for parent in HERE.parents:
        if (parent / "scripts/run_safe.sh").is_file():
            return parent
        sibling_checkout = parent / "adamas"
        if (sibling_checkout / "scripts/run_safe.sh").is_file():
            return sibling_checkout
    raise RuntimeError("set ADAMAS_ROOT to the Adamas checkout")

ROOT = None
SAFE = None
ORIGINAL = None
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n")
POSITIVE = ('explicit_int64_return_in_int8_method', 'explicit_int64_fallthrough_in_int8_method', 'valid_union_annotation_live_exits', 'valid_nil_annotation_discards_value', 'method_pointer_control', 'contextual_alias_annotation', 'bound_generic_annotation', 'typeof_annotation', 'rooted_alias_annotation', 'source_declared_c_short_aliases', 'typeof_distinct_method_locals')
NEGATIVE = ('reject_int8_explicit_int64_return', 'reject_int8_int64_fallthrough', 'reject_string_explicit_int64_return', 'reject_string_int64_fallthrough', 'reject_int32_literal_under_int8', 'reject_bool_under_int32', 'reject_invalid_union_arm', 'reject_unknown_result_annotation', 'reject_unknown_argument_annotation', 'reject_void_annotation_value', 'reject_unknown_pointer_argument', 'reject_unknown_union_result', 'reject_unknown_tuple_argument', 'reject_undeclared_c_short_argument', 'reject_undeclared_c_long_result', 'reject_undeclared_io_argument', 'reject_undeclared_path_argument', 'reject_undeclared_set_argument', 'reject_undeclared_iterator_argument', 'reject_undeclared_uint_argument', 'reject_undeclared_pointer_io_argument')


def footer(raw: bytes, expected: int) -> bytes:
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing safe-run records"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1
    a, b = EXIT.fullmatch(lines[-2]), RESOURCE.fullmatch(lines[-1])
    assert a and b, "malformed safe-run footer"
    assert int(a[1]) == expected and int(b[1]) == expected
    return lines[-2] + lines[-1]


def diagnostic_matches(case: str, output: bytes) -> bool:
    expected = (FIXTURES / (case + ".reject")).read_bytes().strip()
    # Parenthesizing a union in an otherwise identical semantic error is
    # formatting only. Keep both expected and actual type identities strict.
    if case == "reject_invalid_union_arm":
        matched = re.search(rb"expected Proc to return \(?(Int32 \| String)\)?, not Bool", output) is not None
    else:
        matched = expected in output
    return (matched and b"Parse error" not in output and
            b"SIGSEGV" not in output and b"stack overflow" not in output.lower())


def self_test():
    for case in NEGATIVE:
        expected = (FIXTURES / (case + ".reject")).read_bytes().strip()
        assert diagnostic_matches(case, b"Error: " + expected + b"\n")
        assert not diagnostic_matches(case, b"Error: unrelated error\n")
        assert not diagnostic_matches(case, b"Error: " + expected + b"\nParse error\n")
        assert not diagnostic_matches(case, b"SIGSEGV\nError: " + expected + b"\n")
    good_footer = b"[EXIT: 0] after ~0.01s\n[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=0 elapsed_ms=1 peak_rss_bytes=2\n"
    assert footer(good_footer, 0) == good_footer
    noisy_runtime_stderr = b"noise\n" + good_footer
    assert noisy_runtime_stderr != footer(noisy_runtime_stderr, 0)
    print("PASS diagnostic/footer self-tests")


def run_case(label: str, compiler: Path, case: str, work: Path, positive: bool):
    src = FIXTURES / (case + ".cr")
    binary = work / (label + "." + case + ".program")
    cache = work / (label + "." + case + ".cache")
    cache.mkdir()
    env = {**os.environ, "CRYSTAL_CACHE_DIR": str(cache), "ADAMAS_LLVM_CACHE": "0"}
    if label == "original":
        args = ["build", "--no-debug", "--prelude=empty"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        args += [str(src), "-o", str(binary)]
    else:
        args = [str(src), "--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache", "-o", str(binary)]
    result = subprocess.run([str(SAFE), str(compiler), "120", "4096", *args], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145)
    (work / (label + "." + case + ".compile.log")).write_bytes(result.stdout)
    expected_status = 0 if positive else 1
    assert result.returncode == expected_status, f"{label}:{case} compile rc={result.returncode}: {result.stdout!r}"
    footer(result.stdout, expected_status)
    if not positive:
        assert not binary.exists(), f"rejected case produced executable: {case}"
        expected = (FIXTURES / (case + ".reject")).read_bytes().strip()
        if label == "original":
            assert str(src).encode() in result.stdout and diagnostic_matches(case, result.stdout), result.stdout
        else:
            assert diagnostic_matches(case, result.stdout), result.stdout
        print(f"PASS[{label}:{case}] rejection", flush=True)
        return
    assert binary.is_file(), f"missing executable: {case}"
    runtime = subprocess.run([str(SAFE), str(binary), "5", "512"],
                             env={**env, "RUN_SAFE_PASSTHROUGH_STDIO": "1"},
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    (work / (label + "." + case + ".stdout")).write_bytes(runtime.stdout)
    (work / (label + "." + case + ".stderr")).write_bytes(runtime.stderr)
    assert runtime.returncode == 0, f"{label}:{case} runtime rc={runtime.returncode}"
    assert runtime.stderr == footer(runtime.stderr, 0), runtime.stderr
    expected = (FIXTURES / (case + ".expected")).read_bytes()
    assert runtime.stdout == expected, f"{label}:{case} stdout={runtime.stdout!r}, expected={expected!r}"
    print(f"PASS[{label}:{case}] stdout={runtime.stdout!r}", flush=True)


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    global ROOT, SAFE, ORIGINAL
    ROOT = find_root()
    SAFE = Path(os.environ.get("ADAMAS_RUN_SAFE", str(ROOT / "scripts/run_safe.sh"))).resolve()
    original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
    ORIGINAL = Path(shutil.which(original_name) or original_name).resolve()
    assert len(sys.argv) <= 2, "usage: run.py [candidate-adamas]"
    candidate = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT / "bin/adamas"
    assert all(p.is_file() and os.access(p, os.X_OK) for p in (SAFE, ORIGINAL, candidate))
    output = os.environ.get("PROC_LITERAL_ANNOTATION_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists()
        work.mkdir()
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_proc_literal_annotation_"))
    passed = False
    try:
        for label, compiler in (("original", ORIGINAL), ("candidate", candidate)):
            failures = []
            for positive, cases in ((True, POSITIVE), (False, NEGATIVE)):
                for case in cases:
                    try:
                        run_case(label, compiler, case, work, positive)
                    except Exception as exc:
                        failures.append((case, str(exc)))
                        print(f"FAIL[{label}:{case}] {exc}", flush=True)
            assert not failures, f"{label} failures: {failures}"
            print(f"{label.upper()}_PASS_COMPLETE[proc_literal_annotation]", flush=True)
        passed = True
    finally:
        for binary in work.glob("*.program*"):
            binary.unlink()
        for cache in work.glob("*.cache"):
            shutil.rmtree(cache)
        if passed and not output:
            shutil.rmtree(work)
        else:
            print("kept_logs=" + str(work), file=sys.stderr)

if __name__ == "__main__":
    main()
