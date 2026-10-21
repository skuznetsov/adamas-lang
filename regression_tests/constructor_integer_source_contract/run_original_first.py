#!/usr/bin/env python3
"""Original-first numeric literal autocast controls for constructor arguments."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(os.environ.get("ADAMAS_ROOT", str(Path(__file__).resolve().parents[2])))
REPO_ROOT = Path(os.environ.get("ADAMAS_REPO_ROOT", str(ROOT)))
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SAFE = Path(os.environ.get("ADAMAS_RUN_SAFE", str(REPO_ROOT / "scripts/run_safe.sh")))
original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
PINNED = Path(shutil.which(original_name) or original_name).resolve()
EXIT_LINE = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE_LINE = re.compile(
    rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit "
    rb"exit_code=([0-9]+)(?: [a-zA-Z0-9_]+=[a-zA-Z0-9_.,:-]+)+\n"
)
POSITIVE = ['direct_zero_literal', 'typed_constant_zero_control', 'generic_nested_zero_literal', 'signed_minimum_literal', 'uint32_maximum_literal', 'runtime_uint32_local_control', 'runtime_slot_and_zero_literal', 'flow_rebound_uint32_control']
NEGATIVE = ['signed_int32_variable_not_uint32', 'untyped_constant_zero_is_not_literal_autocast', 'signed_literal_below_int32', 'negative_literal_not_uint32', 'literal_above_uint32', 'wrong_later_bool_argument', 'signed_int32_param_not_uint32', 'flow_rebound_int32_not_uint32', 'runtime_int32_expression_not_uint32', 'runtime_int32_method_not_uint32']


def check_status(actual, expected, label):
    if actual != expected:
        raise RuntimeError(f"{label}: expected status {expected}, got {actual}")


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


def first_error(raw):
    for line in raw.decode(errors="replace").splitlines():
        if re.match(r"^\s*error:\s*instantiating\b", line, re.I):
            continue
        if re.search(r"\bwhile requiring\b", line, re.I):
            continue
        if re.match(r"^\s*error:", line, re.I):
            return line
    return ""


def parser_error(line):
    return re.search(r"syntax error|unexpected token|expecting token|unterminated|unclosed|invalid syntax", line, re.I) is not None


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
        args = ["build", "--no-debug", "--error-trace", "--prelude=empty"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        args += [str(fixture), "-o", str(binary)]
    else:
        env["ADAMAS_LLVM_CACHE"] = "0"
        args = [str(fixture), "--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache", "-o", str(binary)]
    result = subprocess.run([str(SAFE), str(host), "60", "2048", *args], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=75)
    log = work / f"{stage}.{name}.compile.log"
    log.write_bytes(result.stdout)
    shutil.rmtree(cache)
    return binary, result, log


def require_positive(stage, host, name, work):
    binary, result, log = compile_case(stage, host, name, work)
    raw = log.read_bytes()
    check_status(result.returncode, 0, f"{stage}:{name} compile")
    if not binary.is_file():
        raise RuntimeError(f"{stage}:{name} successful compile produced no binary")
    safe_footer(raw, 0)
    env = os.environ.copy()
    env["RUN_SAFE_PASSTHROUGH_STDIO"] = "1"
    result = subprocess.run([str(SAFE), str(binary), "5", "512"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    (work / f"{stage}.{name}.stdout").write_bytes(result.stdout)
    check_status(result.returncode, 0, f"{stage}:{name} runtime")
    footer = safe_footer(result.stderr, 0)
    if result.stderr != footer:
        raise RuntimeError(f"{stage}:{name} unexpected runtime stderr {result.stderr!r}")
    expected = (FIXTURES / f"{name}.expected").read_bytes()
    if result.stdout != expected:
        raise RuntimeError(f"{stage}:{name} stdout {result.stdout!r}, expected {expected!r}")
    binary.unlink()
    print(f"PASS[{stage}:{name}] stdout={result.stdout!r}", flush=True)


def require_negative(stage, host, name, work):
    stage_pattern = FIXTURES / f"{name}.{stage}.reject"
    pattern_path = stage_pattern if stage_pattern.is_file() else FIXTURES / f"{name}.reject"
    pattern = pattern_path.read_text().strip()
    binary, result, log = compile_case(stage, host, name, work)
    raw = log.read_bytes()
    check_status(result.returncode, 1, f"{stage}:{name}")
    if binary.exists():
        raise RuntimeError(f"{stage}:{name} rejection left output binary")
    safe_footer(raw, 1)
    error = first_error(raw)
    if not error or parser_error(error) or not re.search(pattern, error, re.I):
        raise RuntimeError(f"{stage}:{name} primary diagnostic mismatch: {error!r}")
    print(f"PASS[{stage}:{name}] {error}", flush=True)


def collect(stage, host, work):
    failures = []
    for name in POSITIVE:
        try:
            require_positive(stage, host, name, work)
        except Exception as exc:
            failures.append(f"{name}: {exc}")
            print(f"FAIL[{stage}:{name}] {exc}", flush=True)
    for name in NEGATIVE:
        try:
            require_negative(stage, host, name, work)
        except Exception as exc:
            failures.append(f"{name}: {exc}")
            print(f"FAIL[{stage}:{name}] {exc}", flush=True)
    if failures:
        raise RuntimeError(f"{stage} stage failures: {failures!r}")


def main():
    assert len(sys.argv) == 2, "usage: run_original_first.py CANDIDATE_HOST"
    candidate = Path(sys.argv[1]).resolve()
    assert SAFE.is_file() and PINNED.is_file() and candidate.is_file()
    fixture_stems = {path.stem for path in FIXTURES.glob("*.cr")}
    assert fixture_stems == set(POSITIVE + NEGATIVE)
    work = Path(tempfile.mkdtemp(prefix="adamas_constructor_literal_autocast_"))
    success = False
    try:
        if not os.environ.get("CRYSTAL_PATH"):
            result = subprocess.run([str(SAFE), str(PINNED), "10", "1024", "env", "CRYSTAL_PATH"], env={**os.environ, "RUN_SAFE_PASSTHROUGH_STDIO": "1"}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            check_status(result.returncode, 0, "original CRYSTAL_PATH")
            footer = safe_footer(result.stderr, 0)
            assert result.stderr == footer
            os.environ["CRYSTAL_PATH"] = result.stdout.decode().strip()
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
