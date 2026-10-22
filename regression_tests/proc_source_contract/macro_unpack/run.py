#!/usr/bin/env python3
"""Original-first no-prelude checks for macro BlockNode.unpacks normalization and AST API."""
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
        sibling_checkout = parent / "adamas"
        if (sibling_checkout / "scripts/run_safe.sh").is_file():
            return sibling_checkout
    raise RuntimeError("set ADAMAS_ROOT to the Adamas checkout")

ROOT = find_repo_root()
FIXTURES = Path(__file__).resolve().parent / "proc_constructor_contract"
SAFE = Path(os.environ.get("ADAMAS_RUN_SAFE", str(ROOT / "scripts/run_safe.sh")))
ORIGINAL_NAME = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
ORIGINAL = Path(shutil.which(ORIGINAL_NAME) or ORIGINAL_NAME).resolve()
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n")
POSITIVE = [
    "macro_args_chained_index",
    "macro_args_index_variable",
    "macro_unpack_forwarding",
    "macro_unpack_nested_forwarding",
    "macro_unpack_ignored_leaf",
    "macro_unpack_second_slot",
    "macro_block_without_unpack",
    "macro_unpack_source_forwarding",
    "macro_unpack_flat_rest",
    "macro_unpack_nested_splat",
    "macro_unpack_repeated_ignored",
    "macro_unpack_two_slots",
    "macro_unpack_caller_local_preservation",
]
NEGATIVE = {
    "reject_candidate_only_var_name": b"undefined macro method 'Var#name'",
    "reject_candidate_only_splat_expr": b"undefined macro method 'Splat#expr'",
    "reject_candidate_only_multi_assign_value": b"undefined macro method 'MultiAssign#value'",
}

def footer(raw, expected):
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing safe-run records"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1
    exit_match, resource_match = EXIT.fullmatch(lines[-2]), RESOURCE.fullmatch(lines[-1])
    assert exit_match and resource_match, "malformed safe-run records"
    assert int(exit_match[1]) == expected and int(resource_match[1]) == expected
    return lines[-2] + lines[-1]

def case_run(label, compiler, case, work):
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
    assert compiled.returncode == 0, f"{label}:{case} compile status {compiled.returncode}: {compiled.stdout!r}"
    footer(compiled.stdout, 0)
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

def case_reject(label, compiler, case, diagnostic, work):
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
    result = subprocess.run([str(SAFE), str(compiler), "120", "4096", *args], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145)
    (work / (label + "." + case + ".compile.log")).write_bytes(result.stdout)
    assert result.returncode == 1, f"{label}:{case} expected semantic rc1 rejection, got {result.returncode}"
    assert not binary.exists(), f"{label}:{case} rejected source emitted executable"
    footer(result.stdout, result.returncode)
    assert diagnostic in result.stdout, f"{label}:{case} missing {diagnostic!r}: {result.stdout!r}"
    print(f"PASS[{label}:{case}] rejected {diagnostic.decode()}", flush=True)

def self_test_footer():
    sample = (b"[EXIT: 0] after ~0.01s\n"
              b"[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=0 elapsed_ms=10 rss_kb=1 fd_count=1\n")
    assert footer(sample, 0) == sample
    try:
        footer(sample.replace(b"exit_code=0", b"exit_code=1"), 0)
    except AssertionError:
        pass
    else:
        raise AssertionError("footer accepted a mismatched resource status")
    assert len(POSITIVE) == 13
    assert set(NEGATIVE) == {
        "reject_candidate_only_var_name",
        "reject_candidate_only_splat_expr",
        "reject_candidate_only_multi_assign_value",
    }
    for case, diagnostic in NEGATIVE.items():
        assert diagnostic.startswith(b"undefined macro method '") and diagnostic.endswith(b"'")
        assert (FIXTURES / (case + ".cr")).is_file()
    for case in POSITIVE:
        assert (FIXTURES / (case + ".cr")).is_file()
        assert (FIXTURES / (case + ".expected")).is_file()

def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test_footer()
        print("PASS safe-run footer self-test")
        return
    assert len(sys.argv) <= 2, "usage: run.py [candidate-adamas]"
    candidate = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT / "bin/adamas"
    assert all(p.is_file() and os.access(p, os.X_OK) for p in (SAFE, ORIGINAL, candidate))
    output = os.environ.get("MACRO_UNPACK_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists()
        work.mkdir()
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_macro_unpack_"))
    passed = False
    try:
        for label, compiler in (("original", ORIGINAL), ("candidate", candidate)):
            failures = []
            for case in POSITIVE:
                try:
                    case_run(label, compiler, case, work)
                except Exception as exc:
                    failures.append((case, str(exc)))
                    print(f"FAIL[{label}:{case}] {exc}", flush=True)
            for case, diagnostic in NEGATIVE.items():
                try:
                    case_reject(label, compiler, case, diagnostic, work)
                except Exception as exc:
                    failures.append((case, str(exc)))
                    print(f"FAIL[{label}:{case}] {exc}", flush=True)
            assert not failures, f"{label} failures: {failures}"
            print(f"{label.upper()}_PASS_COMPLETE[macro_unpack]", flush=True)
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
