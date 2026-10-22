#!/usr/bin/env python3
"""Preserve command-call parsing throughout a logical right-hand-side expression."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(os.environ.get("ADAMAS_ROOT", str(Path(__file__).resolve().parent.parent)))
FIXTURES = Path(__file__).resolve().parent / "logical_rhs_command_calls"
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


POSITIVE = ['direct_command_rhs', 'grouped_command_rhs', 'nested_grouped_command_rhs', 'nested_logical_command_rhs', 'comma_argument_command_rhs', 'grouped_raise_command_rhs', 'nested_command_rhs', 'grouped_nested_command_rhs', 'comma_owner_nested_command_rhs', 'comma_owner_grouped_sibling_rhs']
NEGATIVE = ["reject_grouped_wrong_argument_type", "reject_unclosed_grouped_rhs"]


def rejection(label, case, source, output):
    lines = output.splitlines()
    errors = [i for i, text in enumerate(lines) if re.match(rb"^[Ee]rror: ", text)]
    assert errors, output
    first = errors[0]
    if case == "reject_grouped_wrong_argument_type":
        expected = (b"Error: expected argument #1 to 'emit_byte' to be Int32, not String"
                    if label == "original" else
                    b"error: no overload matches emit_byte for argument types (String)")
        assert lines[first] == expected, output
        if label == "original":
            locations = [text for text in lines[:first] if re.fullmatch(rb"In .+\.cr:[0-9]+:[0-9]+", text)]
            assert locations and locations[-1] == f"In {source}:14:29".encode(), output
        else:
            assert not any(re.match(rb"^.+\.cr:[0-9]+:[0-9]+", text) for text in lines[:first]), output
        return
    if label == "original":
        assert lines[first] == b"Error: expecting token ')', not 'EOF'", output
        locations = [text for text in lines[:first] if re.fullmatch(rb"In .+\.cr:[0-9]+:[0-9]+", text)]
        assert locations and locations[-1] == f"In {source}:15:1".encode(), output
    else:
        located = [i for i, text in enumerate(lines) if re.match(rb"^.+\.cr:[0-9]+:[0-9]+-[0-9]+:[0-9]+ ", text)]
        assert located and located[0] < first, output
        assert lines[located[0]] == f"{source}:15:1-15:1 expecting token: ), not EOF".encode(), output
        assert lines[first] == b"error: compilation failed due to parser errors", output


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
        rejection(label, case, source, compiled.stdout)
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
    assert len(sys.argv) <= 2, "usage: logical_rhs_command_calls_repro.sh [candidate-adamas]"
    candidate = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT / "bin/adamas"
    assert all(p.is_file() and os.access(p, os.X_OK) for p in (SAFE, ORIGINAL, candidate))
    output = os.environ.get("LOGICAL_RHS_COMMAND_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists()
        work.mkdir()
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_logical_rhs_command_"))
    passed = False
    try:
        for label, compiler in (("original", ORIGINAL), ("candidate", candidate)):
            for case in POSITIVE:
                case_run(label, compiler, case, work, True)
            for case in NEGATIVE:
                case_run(label, compiler, case, work, False)
            print(f"{label.upper()}_PASS_COMPLETE[logical_rhs_command_calls]", flush=True)
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
