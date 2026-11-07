#!/usr/bin/env python3
"""Original-first source rest binding regression runner."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
FIXTURE_DIR = SCRIPT_DIR / "fixtures" / "source_rest_shape"
MANIFEST_PATH = FIXTURE_DIR / "cases.json"
COMPILE_TIMEOUT = os.environ.get("REST_SOURCE_COMPILE_TIMEOUT_SEC", "180")
COMPILE_MEMORY = os.environ.get("REST_SOURCE_COMPILE_MAX_MEM_MB", "8192")
RUN_TIMEOUT = os.environ.get("REST_SOURCE_RUN_TIMEOUT_SEC", "5")
RUN_MEMORY = os.environ.get("REST_SOURCE_RUN_MAX_MEM_MB", "512")
ONLY_ORIGINAL = os.environ.get("ONLY_ORIGINAL", "0") == "1"


def fail(message: str) -> None:
    raise SystemExit(message)


def resolve_root(candidate_hint: str | None) -> tuple[Path, Path | None]:
    root_hint = os.environ.get("ADAMAS_ROOT")
    if root_hint:
        root = Path(root_hint).expanduser().resolve()
        if candidate_hint:
            candidate = Path(candidate_hint).expanduser().resolve()
            if candidate.is_dir() and (candidate / "scripts" / "run_safe.sh").is_file():
                return root, None
            return root, candidate
        return root, None
    if not candidate_hint:
        fail("set ADAMAS_ROOT or pass an Adamas binary")
    candidate = Path(candidate_hint).expanduser().resolve()
    if candidate.is_dir() and (candidate / "scripts" / "run_safe.sh").is_file():
        return candidate, None
    if candidate.parent.name == "bin":
        return candidate.parent.parent, candidate
    if (candidate / "scripts" / "run_safe.sh").is_file():
        return candidate, None
    fail("cannot infer ADAMAS_ROOT from candidate: " + str(candidate))


def validate_manifest() -> tuple[list[dict], list[dict]]:
    manifest = json.loads(MANIFEST_PATH.read_text())
    if manifest.get("schema") != "adamas_source_rest_binding_regression_v1":
        fail("unexpected fixture manifest schema")
    cases = manifest.get("cases")
    if not isinstance(cases, list) or len(cases) != 21:
        fail("manifest must contain exactly 21 cases")
    if manifest.get("counts") != {"positive": 18, "negative": 3, "total": 21}:
        fail("manifest case counts changed")
    names: set[str] = set()
    positive: list[dict] = []
    negative: list[dict] = []
    for case in cases:
        name = case.get("name")
        if not isinstance(name, str) or name in names:
            fail("missing or duplicate case name")
        names.add(name)
        source = FIXTURE_DIR / case["source"]
        if not source.is_file():
            fail("missing fixture source: " + str(source))
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest != case.get("source_sha256"):
            fail("source SHA-256 mismatch: " + name)
        if case.get("ok") is True:
            expected = FIXTURE_DIR / (name + ".expected")
            if not expected.is_file() or expected.read_bytes() != case["expected_stdout"].encode():
                fail("expected output mismatch: " + name)
            positive.append(case)
        elif case.get("ok") is False:
            for phase, key in (
                ("original", "original_diagnostic_fragments"),
                ("candidate", "candidate_diagnostic_fragments"),
            ):
                path = FIXTURE_DIR / (name + "." + phase + ".reject")
                rows = [line.strip() for line in path.read_text().splitlines() if line.strip()]
                if rows != case.get(key) or not rows:
                    fail("diagnostic sidecar mismatch: " + name + "/" + phase)
            negative.append(case)
        else:
            fail("case must declare boolean ok: " + name)
    if len(positive) != 18 or len(negative) != 3:
        fail("unexpected positive/negative case split")
    return positive, negative


def resource_footer_ok(data: bytes, expected_exit: int) -> bool:
    resource = re.search(
        rb"(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z",
        data,
    )
    if resource is None:
        return False
    footer = resource.group(0)
    expected = str(expected_exit).encode()
    if (
        b"outcome=exit" not in footer
        or b"reason=exit" not in footer
        or b"exit_code=" + expected not in footer
    ):
        return False
    prior = data[: resource.start()]
    exit_line = re.search(
        rb"(?m)^\[EXIT: " + expected + rb"\] after ~[0-9]+(?:\.[0-9]+)? ?s\n?\Z",
        prior,
    )
    return exit_line is not None


def require_footer(path: Path, expected_exit: int) -> None:
    if not resource_footer_ok(path.read_bytes(), expected_exit):
        fail("run_safe footer mismatch in " + str(path))


def safe_environment(crystal_path: str | None = None, **extra: str) -> dict[str, str]:
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": os.environ.get("HOME", "/tmp"),
        "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
        "LC_ALL": "C",
        "LANG": "C",
    }
    if crystal_path:
        env["CRYSTAL_PATH"] = crystal_path
    for name in ("LIBRARY_PATH", "CRYSTAL_LIBRARY_PATH", "ADAMAS_EXTRA_LINK_FLAGS"):
        value = os.environ.get(name)
        if value:
            env[name] = value
    env.update(extra)
    return env


def get_crystal_path(original: Path, safe_run: Path, work: Path) -> str:
    out = work / "crystal_path.stdout"
    err = work / "crystal_path.stderr"
    env = safe_environment(RUN_SAFE_PASSTHROUGH_STDIO="1")
    command = [str(safe_run), str(original), "10", "1024", "env", "CRYSTAL_PATH"]
    with out.open("wb") as stdout, err.open("wb") as stderr:
        completed = subprocess.run(command, env=env, stdout=stdout, stderr=stderr, check=False)
    require_footer(err, 0)
    if completed.returncode != 0:
        fail("could not read CRYSTAL_PATH from original Crystal")
    value = out.read_text().strip()
    if not value or "\n" in value:
        fail("original Crystal returned an invalid CRYSTAL_PATH")
    return value


def check_compile_log(path: Path, status: int) -> None:
    require_footer(path, status)


def compile_case(
    stage: str,
    source: Path,
    output: Path,
    log: Path,
    cache: Path,
    original: Path,
    candidate: Path | None,
    safe_run: Path,
    crystal_path: str,
) -> int:
    cache.mkdir(parents=True, exist_ok=True)
    env = safe_environment(
        crystal_path,
        CRYSTAL_CACHE_DIR=str(cache),
        ADAMAS_LLVM_CACHE="0",
    )
    if stage == "original":
        args = [
            str(safe_run), str(original), COMPILE_TIMEOUT, COMPILE_MEMORY,
            "build", "--no-debug", "--prelude=empty",
        ]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        args.extend([str(source), "-o", str(output)])
    else:
        if candidate is None:
            fail("candidate binary is required for candidate phase")
        args = [
            str(safe_run), str(candidate), COMPILE_TIMEOUT, COMPILE_MEMORY,
            str(source), "--no-prelude", "--no-debug", "--no-ast-cache",
            "--no-llvm-cache", "-o", str(output),
        ]
    with log.open("wb") as stream:
        completed = subprocess.run(args, env=env, stdout=stream, stderr=subprocess.STDOUT, check=False)
    return completed.returncode


def run_positive(
    stage: str,
    case: dict,
    work: Path,
    original: Path,
    candidate: Path | None,
    safe_run: Path,
    crystal_path: str,
) -> bool:
    name = case["name"]
    source = FIXTURE_DIR / case["source"]
    output = work / (stage + "." + name + ".program")
    compile_log = work / (stage + "." + name + ".compile.log")
    cache = work / ("cache." + stage + "." + name)
    status = compile_case(stage, source, output, compile_log, cache, original, candidate, safe_run, crystal_path)
    if status != 0 or not output.is_file() or not os.access(output, os.X_OK):
        print("COMPILE_FAIL[" + stage + ":" + name + "] status=" + str(status), file=sys.stderr)
        print(compile_log.read_text(errors="replace")[-5000:], file=sys.stderr)
        return False
    try:
        check_compile_log(compile_log, 0)
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return False
    stdout_path = work / (stage + "." + name + ".stdout")
    stderr_path = work / (stage + "." + name + ".stderr")
    env = safe_environment(crystal_path, RUN_SAFE_PASSTHROUGH_STDIO="1")
    args = [str(safe_run), str(output), RUN_TIMEOUT, RUN_MEMORY]
    with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
        completed = subprocess.run(args, env=env, stdout=stdout, stderr=stderr, check=False)
    if completed.returncode != 0:
        print("RUN_FAIL[" + stage + ":" + name + "] status=" + str(completed.returncode), file=sys.stderr)
        print(stderr_path.read_text(errors="replace")[-3000:], file=sys.stderr)
        return False
    try:
        require_footer(stderr_path, 0)
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return False
    raw_stderr = stderr_path.read_bytes()
    resource = re.search(rb"(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z", raw_stderr)
    if resource is None:
        return False
    prior = raw_stderr[: resource.start()]
    exit_line = re.search(rb"(?m)^\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n?\Z", prior)
    if exit_line is None or prior[: exit_line.start()]:
        print("runtime stderr contains output beyond run_safe footer: " + name, file=sys.stderr)
        return False
    expected = (FIXTURE_DIR / (name + ".expected")).read_bytes()
    if stdout_path.read_bytes() != expected:
        print("OUTPUT_MISMATCH[" + stage + ":" + name + "]", file=sys.stderr)
        return False
    print("PASS[" + stage + ":" + name + "]")
    return True


def run_negative(
    stage: str,
    case: dict,
    work: Path,
    original: Path,
    candidate: Path | None,
    safe_run: Path,
    crystal_path: str,
) -> bool:
    name = case["name"]
    source = FIXTURE_DIR / case["source"]
    output = work / (stage + "." + name + ".program")
    output.unlink(missing_ok=True)
    compile_log = work / (stage + "." + name + ".compile.log")
    cache = work / ("cache." + stage + "." + name)
    status = compile_case(stage, source, output, compile_log, cache, original, candidate, safe_run, crystal_path)
    if status != 1 or output.exists():
        print("NEGATIVE_CONTRACT_FAIL[" + stage + ":" + name + "] status=" + str(status), file=sys.stderr)
        print(compile_log.read_text(errors="replace")[-5000:], file=sys.stderr)
        return False
    try:
        check_compile_log(compile_log, 1)
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return False
    raw = compile_log.read_text(errors="replace")
    phase_file = FIXTURE_DIR / (name + "." + stage + ".reject")
    fragments = [line.strip() for line in phase_file.read_text().splitlines() if line.strip()]
    missing = [fragment for fragment in fragments if fragment not in raw]
    if missing:
        print("NEGATIVE_DIAGNOSTIC_FAIL[" + stage + ":" + name + "] missing " + repr(missing), file=sys.stderr)
        print(raw[-5000:], file=sys.stderr)
        return False
    if not re.search(r"(?i)(no overload matches|expected argument #[0-9]+)", raw):
        print("negative did not produce an overload/type-restriction error: " + name, file=sys.stderr)
        return False
    if re.search(r"(?i)(internal compiler error|unhandled exception|segmentation fault|stack overflow)", raw):
        print("compiler crash is not an acceptable negative: " + name, file=sys.stderr)
        return False
    print("PASS[" + stage + ":" + name + "]")
    return True


def qualify(
    stage: str,
    positives: list[dict],
    negatives: list[dict],
    work: Path,
    original: Path,
    candidate: Path | None,
    safe_run: Path,
    crystal_path: str,
) -> bool:
    ok = True
    for case in positives:
        ok = run_positive(stage, case, work, original, candidate, safe_run, crystal_path) and ok
    for case in negatives:
        ok = run_negative(stage, case, work, original, candidate, safe_run, crystal_path) and ok
    return ok


def main() -> int:
    if len(sys.argv) > 2:
        fail("usage: source_rest_shape_runner.py [/path/to/adamas-bin]")
    positives, negatives = validate_manifest()
    candidate_hint = sys.argv[1] if len(sys.argv) == 2 else os.environ.get("ADAMAS_BIN")
    root, candidate_from_root = resolve_root(candidate_hint)
    candidate = candidate_from_root
    if candidate is None:
        candidate = (root / "bin" / "adamas").resolve()
    original_hint = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
    original_value = original_hint if "/" in original_hint else shutil.which(original_hint)
    if not original_value:
        fail("missing original Crystal executable: " + original_hint)
    original = Path(original_value).expanduser().resolve()
    safe_hint = os.environ.get("ADAMAS_RUN_SAFE")
    safe_run = Path(safe_hint).expanduser().resolve() if safe_hint else root / "scripts" / "run_safe.sh"
    if not safe_run.is_file() or not os.access(safe_run, os.X_OK):
        fail("missing run_safe executable: " + str(safe_run))
    if not ONLY_ORIGINAL and (not candidate.is_file() or not os.access(candidate, os.X_OK)):
        fail("missing candidate executable: " + str(candidate))
    runs_root = Path(os.environ.get("REST_SOURCE_RUNS_ROOT", os.environ.get("TMPDIR", "/tmp"))).expanduser()
    runs_root.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="adamas_rest_source_binding.", dir=runs_root))
    keep = False
    try:
        crystal_path = os.environ.get("CRYSTAL_PATH")
        if not crystal_path:
            crystal_path = get_crystal_path(original, safe_run, work)
        if not crystal_path:
            fail("CRYSTAL_PATH is empty")
        if not qualify("original", positives, negatives, work, original, None, safe_run, crystal_path):
            keep = True
            print("ORIGINAL_PASS_INCOMPLETE; candidate phase is blocked.", file=sys.stderr)
            return 1
        print("ORIGINAL_PASS_COMPLETE positives=18 negatives=3")
        if not ONLY_ORIGINAL:
            if not qualify("candidate", positives, negatives, work, original, candidate, safe_run, crystal_path):
                keep = True
                print("CANDIDATE_PASS_INCOMPLETE", file=sys.stderr)
                return 1
            print("CANDIDATE_PASS_COMPLETE positives=18 negatives=3")
        return 0
    finally:
        if keep or os.environ.get("KEEP_ARTIFACTS") == "1":
            print("kept_artifacts=" + str(work), file=sys.stderr)
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
