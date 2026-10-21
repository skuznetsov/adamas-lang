#!/usr/bin/env python3
"""Original Crystal String layout and canonical runtime type-header oracle."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(os.environ.get("ADAMAS_ROOT", str(Path(__file__).resolve().parents[2])))
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SAFE = Path(os.environ.get("ADAMAS_RUN_SAFE", str(ROOT / "adamas/scripts/run_safe.sh")))
original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
PINNED = Path(shutil.which(original_name) or original_name).resolve()
POSITIVES = ['runtime_string_type_headers', 'bool_string_layout']
NEGATIVES = []
EXIT_LINE = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE_LINE = re.compile(
    rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit "
    rb"exit_code=([0-9]+)(?: [a-zA-Z0-9_]+=[a-zA-Z0-9_.,:-]+)+\n"
)


def safe_footer(raw, expected):
    lines = raw.splitlines(keepends=True)
    exits = [i for i, line in enumerate(lines) if line.startswith(b"[EXIT: ")]
    resources = [i for i, line in enumerate(lines) if line.startswith(b"[RUN_SAFE_RESOURCE] ")]
    assert len(exits) == len(resources) == 1, "expected one run_safe footer pair"
    assert exits[0] == len(lines) - 2 and resources[0] == len(lines) - 1, "footer pair must be final"
    assert resources[0] == exits[0] + 1, "footer records must be adjacent"
    em = EXIT_LINE.fullmatch(lines[-2])
    rm = RESOURCE_LINE.fullmatch(lines[-1])
    assert em and rm, "malformed run_safe footer"
    assert int(em.group(1)) == int(rm.group(1)) == expected, "footer status mismatch"
    return lines[-2] + lines[-1]


def compile_case(stage, host, name, work):
    fixture = FIXTURES / f"{name}.cr"
    binary = work / f"{stage}.{name}.program"
    cache = work / f"{stage}.{name}.cache"
    if binary.exists():
        binary.unlink()
    cache.mkdir()
    env = os.environ.copy()
    env["CRYSTAL_CACHE_DIR"] = str(cache)
    if stage == "original":
        args = ["build", "--no-debug", "--error-trace"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        args += [str(fixture), "-o", str(binary)]
    else:
        env["ADAMAS_LLVM_CACHE"] = "0"
        args = [str(fixture), "--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache", "-o", str(binary)]
    result = subprocess.run([str(SAFE), str(host), "60", "2048", *args], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=75)
    log = work / f"{stage}.{name}.compile.log"
    log.write_bytes(result.stdout)
    shutil.rmtree(cache)
    return binary, result, log


def require_positive(stage, host, name, work):
    binary, result, log = compile_case(stage, host, name, work)
    raw = log.read_bytes()
    if result.returncode != 0:
        raise RuntimeError(f"{stage}:{name} compile exit {result.returncode}: {raw!r}")
    if not binary.is_file():
        raise RuntimeError(f"{stage}:{name} successful compile produced no binary")
    safe_footer(raw, 0)
    env = os.environ.copy()
    env["RUN_SAFE_PASSTHROUGH_STDIO"] = "1"
    result = subprocess.run([str(SAFE), str(binary), "5", "512"], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    (work / f"{stage}.{name}.stdout").write_bytes(result.stdout)
    if result.returncode != 0:
        raise RuntimeError(f"{stage}:{name} runtime exit {result.returncode}")
    footer = safe_footer(result.stderr, 0)
    if result.stderr != footer:
        raise RuntimeError(f"{stage}:{name} unexpected runtime stderr {result.stderr!r}")
    expected = (FIXTURES / f"{name}.expected").read_bytes()
    if result.stdout != expected:
        raise RuntimeError(f"{stage}:{name} stdout {result.stdout!r}, expected {expected!r}")
    binary.unlink()
    print(f"PASS[{stage}:{name}] stdout={result.stdout!r}", flush=True)


def primary_diagnostic(raw):
    # Crystal adds instantiation/require context before the causal diagnostic.
    # Ignore only these known wrappers; parser and compiler-internal errors stay
    # first-class diagnostics and cannot be hidden by a later message.
    for line in raw.decode(errors="replace").splitlines():
        if re.match(r"^\s*error:\s*instantiating\b", line, re.I):
            continue
        if re.search(r"\bwhile requiring\b", line, re.I):
            continue
        if re.fullmatch(r"\s*error:\s*expanding macro\s*", line, re.I):
            continue
        if re.match(r"^\s*error:", line, re.I):
            return line.encode()
    return b""


def require_negative(stage, host, name, work):
    binary, result, log = compile_case(stage, host, name, work)
    raw = log.read_bytes()
    if result.returncode != 1:
        raise RuntimeError(f"{stage}:{name} expected safe-wrapper status 1, got {result.returncode}: {raw!r}")
    if binary.exists():
        raise RuntimeError(f"{stage}:{name} rejection left an output binary")
    safe_footer(raw, 1)
    primary = primary_diagnostic(raw)
    if not primary:
        raise RuntimeError(f"{stage}:{name} has no primary semantic diagnostic: {raw!r}")
    if re.search(rb"(?i)(syntax error|unexpected token|unterminated|invalid syntax)", primary):
        raise RuntimeError(f"{stage}:{name} failed with a parser diagnostic: {primary!r}")
    pattern = (FIXTURES / f"{name}.reject").read_text().strip()
    if not re.search(pattern.encode(), primary):
        raise RuntimeError(f"{stage}:{name} primary diagnostic {primary!r} misses {pattern!r}")
    print(f"PASS[{stage}:{name}] rejected by {primary.decode(errors='replace')}", flush=True)


def collect(stage, host, work):
    failures = []
    for name in POSITIVES:
        try:
            require_positive(stage, host, name, work)
        except Exception as exc:
            failures.append(f"{name}: {exc}")
            print(f"FAIL[{stage}:{name}] {exc}", flush=True)
    for name in NEGATIVES:
        try:
            require_negative(stage, host, name, work)
        except Exception as exc:
            failures.append(f"{name}: {exc}")
            print(f"FAIL[{stage}:{name}] {exc}", flush=True)
    if failures:
        raise RuntimeError(f"{stage} stage failures: {failures!r}")


def self_test_primary_diagnostic():
    cases = [
        (b"Error: instantiating 'f(TellOrder32)'\n\nError: method f must return Int64 but it is returning Int32\n", b"Error: method f must return Int64 but it is returning Int32"),
        (b"Error: while requiring ./dependency\nError: undefined constant Missing\n", b"Error: undefined constant Missing"),
        (b"Error: instantiating 'f'\nError: syntax error near token\n", b"Error: syntax error near token"),
        (b"Error: instantiating 'f'\nError: internal compiler error: invalid state\n", b"Error: internal compiler error: invalid state"),
        (b"Error: undefined constant First\nError: undefined constant Later\n", b"Error: undefined constant First"),
    ]
    cases += [
        (b"Error: expanding macro\nError: undefined constant MissingMacroType\n", b"Error: undefined constant MissingMacroType"),
        (b"Error: expanding macro\nError: unexpected token in expansion\n", b"Error: unexpected token in expansion"),
        (b"Error: expanding macro\nError: internal compiler error: invalid state\n", b"Error: internal compiler error: invalid state"),
    ]
    for raw, expected in cases:
        actual = primary_diagnostic(raw)
        assert actual == expected, (raw, actual, expected)
    parser_or_internal = [cases[2][1], cases[3][1]]
    for diagnostic in parser_or_internal:
        assert re.search(rb"(?i)(syntax error|unexpected token|unterminated|invalid syntax|internal compiler error)", diagnostic)


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test_primary_diagnostic()
        print("PASS primary diagnostic context/parser/internal self-tests")
        return
    self_test_primary_diagnostic()
    assert len(sys.argv) == 2, "usage: run_original_first.py CANDIDATE_HOST"
    candidate = Path(sys.argv[1]).resolve()
    assert SAFE.is_file() and PINNED.is_file() and candidate.is_file()
    fixture_stems = {path.stem for path in FIXTURES.glob("*.cr")}
    assert fixture_stems == set(POSITIVES + NEGATIVES)
    work = Path(tempfile.mkdtemp(prefix="adamas_string_header_"))
    success = False
    try:
        collect("original", PINNED, work)
        collect("candidate", candidate, work)
        success = True
    finally:
        for path in work.glob("*.cache"):
            shutil.rmtree(path)
        for path in work.glob("*.program"):
            path.unlink()
        if success and os.environ.get("KEEP_ARTIFACTS") != "1":
            shutil.rmtree(work)
        else:
            print(f"kept_artifacts={work}", file=sys.stderr)


if __name__ == "__main__":
    main()
