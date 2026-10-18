#!/usr/bin/env python3
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

packet = Path(__file__).resolve().parent
fixtures = packet / "fixtures" / "deferred_class_new_dispatch"
candidate_arg = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("ADAMAS_BIN", "")
candidate = Path(candidate_arg).resolve() if candidate_arg else None
adamas_root = Path(os.environ.get("ADAMAS_ROOT", str(packet.parent))).resolve()
if candidate and not adamas_root and candidate.parent.name == "bin":
    adamas_root = candidate.parent.parent
safe_run = Path(os.environ.get("ADAMAS_RUN_SAFE", str(adamas_root / "scripts/run_safe.sh" if adamas_root else "")))
original_hint = os.environ.get("ORIGINAL_CRYSTAL_BIN", "")
stdlib_hint = os.environ.get("ORIGINAL_CRYSTAL_STDLIB", os.environ.get("CRYSTAL_PATH", ""))
if not original_hint or not stdlib_hint:
    raise SystemExit("ORIGINAL_CRYSTAL_BIN and CRYSTAL_PATH are required")
original = Path(original_hint)
stdlib = Path(stdlib_hint)
if not original.is_file() or not os.access(original, os.X_OK):
    raise SystemExit(f"missing original Crystal: {original}")
if not safe_run.is_file() or not os.access(safe_run, os.X_OK):
    raise SystemExit("set ADAMAS_RUN_SAFE or ADAMAS_ROOT")
if not (stdlib / "empty.cr").is_file():
    raise SystemExit(f"missing pinned empty prelude: {stdlib / 'empty.cr'}")
if candidate and (not candidate.is_file() or not os.access(candidate, os.X_OK)):
    raise SystemExit(f"missing candidate compiler: {candidate}")

os.environ["CRYSTAL_PATH"] = str(stdlib)
timeout = os.environ.get("SEQUENCE_COMPILE_TIMEOUT_SEC", "120")
mem = os.environ.get("SEQUENCE_COMPILE_MAX_MEM_MB", "8192")
run_timeout = os.environ.get("SEQUENCE_RUN_TIMEOUT_SEC", "5")
run_mem = os.environ.get("SEQUENCE_RUN_MAX_MEM_MB", "512")
runs_root = Path(os.environ.get("SEQUENCE_RUNS_ROOT", str(Path(os.environ.get("TMPDIR", "/tmp")) / "adamas_deferred_class_new_dispatch")))
runs_root.mkdir(parents=True, exist_ok=True)
fixtures_positive = ("deferred_class_new", "qualified_explicit_new", "synthesized_allocator_fallback")

def successful_safe_footer(path):
    raw = path.read_bytes()
    match = re.search(rb"(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z", raw)
    if not match or b"outcome=exit" not in match.group(0) or b"reason=exit" not in match.group(0) or b"exit_code=0" not in match.group(0):
        return False
    return re.search(rb"(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z", raw[:match.start()]) is not None

def failed_safe_footer(path, expected_status):
    raw = path.read_bytes()
    match = re.search(rb"(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z", raw)
    if not match:
        return False
    resource = match.group(0)
    expected_code = f"exit_code={expected_status}".encode()
    if b"outcome=exit" not in resource or b"reason=exit" not in resource or expected_code not in resource:
        return False
    exit_pattern = rb"(?m)^\[EXIT: " + str(expected_status).encode() + rb"\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z"
    return re.search(exit_pattern, raw[:match.start()]) is not None

def runtime_stderr_clean(path):
    raw = path.read_bytes()
    match = re.search(rb"(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z", raw)
    if not match or b"exit_code=0" not in match.group(0):
        return False
    prefix = raw[:match.start()]
    exit_line = re.search(rb"(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z", prefix)
    return exit_line is not None and not prefix[:exit_line.start()]

def compiler_command(stage, compiler, source, output):
    if stage == "original":
        cmd = [str(safe_run), str(compiler), timeout, mem, "build", "--no-debug", "--prelude=empty"]
        if sys.platform == "darwin":
            cmd.append("--link-flags=-fuse-ld=/usr/bin/ld")
        cmd.extend([str(source), "-o", str(output)])
    else:
        cmd = [str(safe_run), str(compiler), timeout, mem, str(source), "--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache", "-o", str(output)]
    return cmd

def compile_positive(stage, compiler, name, work):
    output = work / f"{stage}.{name}.program"
    log = work / f"{stage}.{name}.compile.log"
    cache = work / f"cache.{stage}.{name}"
    cache.mkdir()
    env = os.environ.copy()
    env["CRYSTAL_CACHE_DIR"] = str(cache)
    if stage != "original":
        env["ADAMAS_LLVM_CACHE"] = "0"
    with log.open("wb") as stream:
        result = subprocess.run(compiler_command(stage, compiler, fixtures / f"{name}.cr", output), env=env, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode != 0 or not output.is_file() or not os.access(output, os.X_OK) or not successful_safe_footer(log):
        raise RuntimeError(f"COMPILE_FAIL[{stage}:{name}] status={result.returncode}; see {log}")
    stdout = work / f"{stage}.{name}.stdout"
    stderr = work / f"{stage}.{name}.stderr"
    run_env = os.environ.copy()
    run_env["RUN_SAFE_PASSTHROUGH_STDIO"] = "1"
    with stdout.open("wb") as out, stderr.open("wb") as err:
        result = subprocess.run([str(safe_run), str(output), run_timeout, run_mem], env=run_env, stdout=out, stderr=err)
    if result.returncode != 0 or not runtime_stderr_clean(stderr):
        raise RuntimeError(f"RUN_FAIL[{stage}:{name}] status={result.returncode}; see {stderr}")
    expected = (fixtures / f"{name}.expected").read_bytes()
    if stdout.read_bytes() != expected:
        raise RuntimeError(f"OUTPUT_MISMATCH[{stage}:{name}]")
    print(f"PASS[{stage}:{name}]")

def compile_rejection(stage, compiler, work):
    name = "wrong_explicit_argument"
    output = work / f"{stage}.{name}.program"
    log = work / f"{stage}.{name}.compile.log"
    cache = work / f"cache.{stage}.{name}"
    cache.mkdir()
    env = os.environ.copy()
    env["CRYSTAL_CACHE_DIR"] = str(cache)
    if stage != "original":
        env["ADAMAS_LLVM_CACHE"] = "0"
    with log.open("wb") as stream:
        result = subprocess.run(compiler_command(stage, compiler, fixtures / f"{name}.cr", output), env=env, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode != 1 or output.exists():
        raise RuntimeError(f"REJECTION_STATUS_OR_ARTIFACT[{stage}:{name}] status={result.returncode} executable={output.exists()}; see {log}")
    if not failed_safe_footer(log, 1):
        raise RuntimeError(f"REJECTION_NOT_CLEAN_EXIT[{stage}:{name}]; see {log}")
    diagnostic = log.read_text(errors="replace")
    expected = (fixtures / f"{name}.{stage}.diagnostic").read_text().splitlines()
    if any(item not in diagnostic for item in expected):
        raise RuntimeError(f"REJECTION_WRONG[{stage}:{name}]; expected tokens {expected}; see {log}")
    print(f"PASS[{stage}:{name}]")

work = Path(tempfile.mkdtemp(prefix="run.", dir=runs_root))
try:
    for name in fixtures_positive:
        compile_positive("original", original, name, work)
    compile_rejection("original", original, work)
    print("ORIGINAL_PASS_COMPLETE[deferred_new_explicit_dispatch]")
    if candidate and os.environ.get("ONLY_ORIGINAL", "0") != "1":
        for name in fixtures_positive:
            compile_positive("candidate", candidate, name, work)
        compile_rejection("candidate", candidate, work)
        print("CANDIDATE_PASS[deferred_new_explicit_dispatch]")
    else:
        print("CANDIDATE_SKIPPED")
except Exception:
    for cache in work.glob("cache.*"):
        shutil.rmtree(cache, ignore_errors=True)
    print(f"kept_artifacts={work}", file=sys.stderr)
    raise
else:
    if os.environ.get("KEEP_ARTIFACTS", "0") == "1":
        print(f"kept_artifacts={work}", file=sys.stderr)
    else:
        shutil.rmtree(work, ignore_errors=True)
