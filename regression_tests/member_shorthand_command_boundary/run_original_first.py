#!/usr/bin/env python3
"""Original-first shared member and shorthand command parser boundary oracle."""
from pathlib import Path
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
ROOT = None
SAFE = None
ORIGINAL = None
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n")
POSITIVE = ['shorthand_command_named_order', 'shorthand_paren_named_order', 'shorthand_command_positional', 'shorthand_paren_positional', 'shorthand_spaced_paren_postfix', 'shorthand_enclosed_named', 'shorthand_signed_command', 'member_command_named', 'member_spaced_paren_postfix', 'member_keyword_command', 'member_bare_boundary']
NEGATIVE = []


def footer(raw: bytes, expected: int) -> bytes:
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing safe-run records"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1
    exit_match, resource_match = EXIT.fullmatch(lines[-2]), RESOURCE.fullmatch(lines[-1])
    assert exit_match and resource_match, "malformed safe-run records"
    assert int(exit_match[1]) == expected and int(resource_match[1]) == expected
    return lines[-2] + lines[-1]


def self_test():
    assert footer(b"build output\n[EXIT: 1] after ~0.2s\n[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=1 wall_s=0.2\n", 1)
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
            raise AssertionError(f"accepted malformed safe footer: {malformed!r}")
    for name in POSITIVE:
        assert (FIXTURES / (name + ".cr")).is_file(), name
        assert (FIXTURES / (name + ".expected")).is_file(), name
    for name in NEGATIVE:
        for suffix in (".cr", ".original.reject", ".candidate.reject"):
            assert (FIXTURES / (name + suffix)).is_file(), name + suffix
    assert len(set(POSITIVE + NEGATIVE)) == len(POSITIVE) + len(NEGATIVE)
    print("PASS static runner self-test", flush=True)


def case_run(label: str, compiler: Path, case: str, work: Path, positive: bool):
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
    compiled = subprocess.run(
        [str(SAFE), str(compiler), "120", "4096", *args], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145,
    )
    (work / (label + "." + case + ".compile.log")).write_bytes(compiled.stdout)
    expected_status = 0 if positive else 1
    assert compiled.returncode == expected_status, (
        f"{label}:{case} compile status {compiled.returncode}: {compiled.stdout!r}"
    )
    footer(compiled.stdout, expected_status)
    if not positive:
        assert not binary.exists(), f"rejected source emitted executable: {case}"
        expected = (FIXTURES / (case + "." + label + ".reject")).read_bytes().strip()
        assert expected in compiled.stdout, f"{label}:{case} missing diagnostic {expected!r}: {compiled.stdout!r}"
        assert b"SIGSEGV" not in compiled.stdout and b"Unhandled exception" not in compiled.stdout
        print(f"PASS[{label}:{case}] source rejection", flush=True)
        return
    assert binary.is_file(), f"missing executable: {case}"
    result = subprocess.run(
        [str(SAFE), str(binary), "5", "512"],
        env={**env, "RUN_SAFE_PASSTHROUGH_STDIO": "1"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
    )
    (work / (label + "." + case + ".stdout")).write_bytes(result.stdout)
    (work / (label + "." + case + ".stderr")).write_bytes(result.stderr)
    assert result.returncode == 0, f"{label}:{case} runtime status {result.returncode}"
    assert result.stderr == footer(result.stderr, 0), result.stderr
    expected = (FIXTURES / (case + ".expected")).read_bytes()
    assert result.stdout == expected, f"{label}:{case} stdout={result.stdout!r}, expected={expected!r}"
    print(f"PASS[{label}:{case}] stdout={result.stdout!r}", flush=True)


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    assert len(sys.argv) <= 2, "usage: run_original_first.py [candidate-adamas]"
    global ROOT, SAFE, ORIGINAL
    ROOT = find_repo_root()
    SAFE = Path(os.environ.get("ADAMAS_RUN_SAFE", str(ROOT / "scripts/run_safe.sh"))).resolve()
    original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
    ORIGINAL = Path(shutil.which(original_name) or original_name).resolve()
    candidate = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT / "bin/adamas"
    assert all(path.is_file() and os.access(path, os.X_OK) for path in (SAFE, ORIGINAL, candidate))
    output = os.environ.get("MEMBER_COMMAND_BOUNDARY_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists()
        work.mkdir(parents=True)
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_member_command_"))
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
            print(f"{label.upper()}_PASS_COMPLETE[member_command_boundary]", flush=True)
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
