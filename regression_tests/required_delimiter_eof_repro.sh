#!/usr/bin/env python3
"""Reject unexpected EOF at required call, grouping, and index boundaries."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(os.environ.get("ADAMAS_ROOT", str(Path(__file__).resolve().parent.parent)))
FIXTURES = Path(__file__).resolve().parent / "required_delimiter_eof"
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


POSITIVE = ["valid_plain_call", "valid_grouped_index_call"]
# Crystal points an unterminated empty call at its opening parenthesis; Adamas
# reports the unexpected EOF. Each diagnostic must be primary and source-bound.
NEGATIVE = {
    "reject_unclosed_call": ((6, 1, "expecting token ')', not 'EOF'"),
                             (6, 1, "expecting token: ), not EOF")),
    "reject_unclosed_grouping": ((2, 1, "unexpected token: EOF"),
                                 (2, 1, "expecting token: ), not EOF")),
    "reject_empty_call_eof": ((5, 8, "unterminated call"),
                             (6, 1, "unexpected EOF")),
    "reject_unclosed_index": ((3, 1, "expecting token ']', not 'EOF'"),
                              (3, 1, "expecting token: ], not EOF")),
}


def rejection(label, case, source, output):
    line, column, message = NEGATIVE[case][0 if label == "original" else 1]
    lines = output.splitlines()
    if label == "original":
        errors = [i for i, text in enumerate(lines) if re.match(rb"^[Ee]rror: ", text)]
        assert errors and lines[errors[0]] == b"Error: " + message.encode(), output
        locations = [text for text in lines[:errors[0]] if re.fullmatch(rb"In .+\.cr:[0-9]+:[0-9]+", text)]
        assert locations and locations[-1] == f"In {source}:{line}:{column}".encode(), output
    else:
        located = [i for i, text in enumerate(lines) if re.match(rb"^.+\.cr:[0-9]+:[0-9]+-[0-9]+:[0-9]+ ", text)]
        assert located, output
        first = located[0]
        assert not any(re.match(rb"^[Ee]rror: ", text) for text in lines[:first]), output
        expected = f"{source}:{line}:{column}-{line}:{column} {message}".encode()
        assert lines[first] == expected, output
        assert b"error: compilation failed due to parser errors" in lines[first+1:], output


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
    assert len(sys.argv) <= 2, "usage: required_delimiter_eof_repro.sh [candidate-adamas]"
    candidate = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT / "bin/adamas"
    assert all(p.is_file() and os.access(p, os.X_OK) for p in (SAFE, ORIGINAL, candidate))
    output = os.environ.get("REQUIRED_DELIMITER_EOF_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists()
        work.mkdir()
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_required_delimiter_eof_"))
    passed = False
    try:
        for label, compiler in (("original", ORIGINAL), ("candidate", candidate)):
            for case in POSITIVE:
                case_run(label, compiler, case, work, True)
            for case in NEGATIVE:
                case_run(label, compiler, case, work, False)
            print(f"{label.upper()}_PASS_COMPLETE[required_delimiter_eof]", flush=True)
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
