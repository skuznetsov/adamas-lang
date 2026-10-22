#!/usr/bin/env python3
"""Compare strict Proc constructor typing and callback ABI with Crystal."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

def find_repo_root():
    if os.environ.get("ADAMAS_ROOT"):
        return Path(os.environ["ADAMAS_ROOT"]).resolve()
    for parent in Path(__file__).resolve().parents:
        if (parent / "scripts/run_safe.sh").is_file():
            return parent
    raise RuntimeError("set ADAMAS_ROOT to the Adamas checkout")

ROOT = find_repo_root()
FIXTURES = Path(__file__).resolve().parent / "proc_constructor_contract"
SAFE = Path(os.environ.get("ADAMAS_RUN_SAFE", str(ROOT / "scripts/run_safe.sh")))
ORIGINAL_NAME = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
ORIGINAL = Path(shutil.which(ORIGINAL_NAME) or ORIGINAL_NAME).resolve()
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n")


def footer(raw, expected):
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing safe-run records"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1
    exit_match, resource_match = EXIT.fullmatch(lines[-2]), RESOURCE.fullmatch(lines[-1])
    assert exit_match and resource_match, "malformed safe-run records"
    assert int(exit_match[1]) == expected and int(resource_match[1]) == expected
    return lines[-2] + lines[-1]


POSITIVE = ['direct_callback', 'arrow_alias_callback', 'ignored_trailing_input', 'all_inputs_ignored', 'sole_tuple_input_unpack', 'splat_with_suffix', 'nil_result_discards_bool', 'void_result_discards_bool', 'noreturn_body', 'explicit_tuple_destructuring_with_another_input', 'custom_new_returns_int32', 'direct_void_nil_same_source', 'aliased_void_nil_same_source', 'arrow_explicit_output', 'multiline_union_control']
NEGATIVE = ['reject_dynamic_wrong_result', 'reject_constant_branch_wrong_result', 'reject_tuple_wrong_result']


def candidate_semantic_rejection_matches(case, output):
    # LoweringError has no source path in its formatter. Match the exact
    # semantic block-result boundary, while rejecting parser errors and crashes.
    actual_types = {
        "reject_dynamic_wrong_result": rb"(?:Int32 \| Bool|Bool \| Int32|Bool)",
        "reject_constant_branch_wrong_result": rb"(?:Int32 \| Bool|Bool \| Int32|Bool)",
        "reject_tuple_wrong_result": rb"Tuple\(Bool\)",
    }
    if case not in actual_types:
        return False
    expected_type = rb"Tuple\(Int32\)" if case == "reject_tuple_wrong_result" else rb"Int32"
    pattern = rb"expected block to return " + expected_type + rb", not " + actual_types[case] + rb"(?:[\r\n]|$)"
    return (re.search(pattern, output) is not None
            and b"Parse error" not in output
            and b"SIGSEGV" not in output)


def self_test_diagnostic_matcher():
    cases = {
        "reject_dynamic_wrong_result": b"Error: expected block to return Int32, not Bool | Int32\n",
        "reject_constant_branch_wrong_result": b"Error: expected block to return Int32, not Bool\n",
        "reject_tuple_wrong_result": b"Error: expected block to return Tuple(Int32), not Tuple(Bool)\n",
    }
    for name, diagnostic in cases.items():
        assert candidate_semantic_rejection_matches(name, diagnostic), name
        assert not candidate_semantic_rejection_matches(name, b"Error: unrelated semantic error\n"), name
        assert not candidate_semantic_rejection_matches(name, diagnostic + b"Parse error\n"), name
    assert not candidate_semantic_rejection_matches("unknown_case", cases["reject_dynamic_wrong_result"])


def case_run(label, compiler, case, work, positive):
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
    compiled = subprocess.run([str(SAFE), str(compiler), "120", "4096", *args], env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145)
    (work / (label + "." + case + ".compile.log")).write_bytes(compiled.stdout)
    status = 0 if positive else 1
    assert compiled.returncode == status, f"{label}:{case} compile status {compiled.returncode}: {compiled.stdout!r}"
    footer(compiled.stdout, status)
    if not positive:
        assert not binary.exists(), f"rejected source emitted an executable: {case}"
        expected = (FIXTURES / (case + "." + label + ".reject")).read_bytes().strip()
        if label == "original":
            assert str(source).encode() in compiled.stdout and expected in compiled.stdout, compiled.stdout
        else:
            assert candidate_semantic_rejection_matches(case, compiled.stdout), compiled.stdout
        print(f"PASS[{label}:{case}] source rejection", flush=True)
        return
    assert binary.is_file(), f"missing executable: {case}"
    result = subprocess.run([str(SAFE), str(binary), "5", "512"],
                            env={**env, "RUN_SAFE_PASSTHROUGH_STDIO": "1"},
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    (work / (label + "." + case + ".stdout")).write_bytes(result.stdout)
    (work / (label + "." + case + ".stderr")).write_bytes(result.stderr)
    assert result.returncode == 0, f"{label}:{case} runtime status {result.returncode}"
    assert result.stderr == footer(result.stderr, 0), result.stderr
    expected = (FIXTURES / (case + ".expected")).read_bytes()
    assert result.stdout == expected, f"{label}:{case} stdout={result.stdout!r}, expected={expected!r}"
    print(f"PASS[{label}:{case}] stdout={result.stdout!r}", flush=True)


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test_diagnostic_matcher()
        print("PASS candidate diagnostic matcher self-test")
        return
    assert len(sys.argv) <= 2, "usage: proc_constructor_contract_repro.sh [candidate-adamas]"
    candidate = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT / "bin/adamas"
    assert all(p.is_file() and os.access(p, os.X_OK) for p in (SAFE, ORIGINAL, candidate))
    output = os.environ.get("PROC_CONSTRUCTOR_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists()
        work.mkdir()
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_proc_constructor_"))
    passed = False
    try:
        for label, compiler in (("original", ORIGINAL), ("candidate", candidate)):
            failures = []
            for positive, names in ((True, POSITIVE), (False, NEGATIVE)):
                for case in names:
                    try:
                        case_run(label, compiler, case, work, positive)
                    except Exception as exc:
                        failures.append((case, str(exc)))
                        print(f"FAIL[{label}:{case}] {exc}", flush=True)
            assert not failures, f"{label} failures: {failures}"
            print(f"{label.upper()}_PASS_COMPLETE[proc_constructor_contract]", flush=True)
        passed = True
    finally:
        for p in work.glob("*.program*"):
            p.unlink()
        for p in work.glob("*.cache"):
            shutil.rmtree(p)
        if passed and not output:
            shutil.rmtree(work)
        else:
            print("kept_logs=" + str(work), file=sys.stderr)


if __name__ == "__main__":
    main()
