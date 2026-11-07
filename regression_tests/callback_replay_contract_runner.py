#!/usr/bin/env python3
"""Stock-first safe runner for the callback source-result fixtures."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


ICE_RE = re.compile(
    r"internal compiler error|unhandled exception|segmentation fault|SIGSEGV|"
    r"invalid memory access|AddressSanitizer|stack overflow",
    re.IGNORECASE,
)
SAFE_FOOTER_RE = re.compile(
    rb"(?m)^\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n"
    rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 "
    rb"outcome=exit reason=exit exit_code=([0-9]+) [^\r\n]+\n?\Z"
)


def fail(message: str) -> "NoReturn":
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def safe_footer(raw: bytes, expected: int, context: str) -> bytes:
    match = SAFE_FOOTER_RE.search(raw)
    if match is None:
        fail(f"{context}: missing strict run_safe exit/resource footer")
    if int(match.group(1)) != expected or int(match.group(2)) != expected:
        fail(f"{context}: unexpected run_safe exit/resource status")
    return raw[:match.start()]


def executable_path(hint: str) -> Path:
    resolved = shutil.which(hint) if "/" not in hint else hint
    return Path(resolved or hint).resolve()


def execute(command: list[str], env: dict[str, str], log: Path) -> subprocess.CompletedProcess[bytes]:
    try:
        result = subprocess.run(
            command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=195, check=False,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or b""
        stderr = exc.stderr or b""
        log.write_bytes(stdout + stderr)
        fail(f"command timed out; see {log}")
    log.write_bytes(result.stdout + result.stderr)
    return result


def check_fixture_hash(case: dict[str, object], fixture_root: Path) -> Path:
    source = fixture_root / str(case["source"])
    if not source.is_file():
        fail(f"missing fixture {source}")
    actual = hashlib.sha256(source.read_bytes()).hexdigest()
    if actual != case.get("sha256"):
        fail(f"fixture hash mismatch for {case['name']}: {actual}")
    return source


def compiler_command(
    stage: str, compiler: Path, source: Path, output: Path, link_flags: str,
) -> list[str]:
    if stage == "original":
        args = ["build", "--prelude=empty", "--no-debug"]
        if link_flags:
            args.append("--link-flags=" + link_flags)
        args.extend([str(source), "-o", str(output)])
    else:
        args = [
            str(source), "--no-prelude", "--no-debug", "--no-ast-cache",
            "--no-llvm-cache", "-o", str(output),
        ]
    return [str(compiler), "180", "8192", *args]


def check_positive(
    case: dict[str, object], stage: str, compiler: Path, safe_runner: Path,
    source: Path, work: Path, env: dict[str, str], link_flags: str,
) -> None:
    name = str(case["name"])
    output = work / f"{stage}-{name}.bin"
    cache = work / f"{stage}-{name}.cache"
    cache.mkdir()
    output.unlink(missing_ok=True)

    compile_env = env.copy()
    compile_env["CRYSTAL_CACHE_DIR"] = str(cache)
    if stage == "candidate":
        compile_env["ADAMAS_LLVM_CACHE"] = "0"
    command = [
        str(safe_runner), *compiler_command(stage, compiler, source, output, link_flags),
    ]
    compile_result = execute(command, compile_env, work / f"{stage}-{name}.compile.log")
    safe_footer(compile_result.stderr, compile_result.returncode, f"{stage}/{name}/compile")
    if compile_result.returncode != 0 or not output.is_file():
        fail(f"{stage}/{name}: expected successful compile")

    runtime_env = env.copy()
    runtime_env["RUN_SAFE_PASSTHROUGH_STDIO"] = "1"
    runtime = execute(
        [str(safe_runner), str(output), "5", "512"],
        runtime_env,
        work / f"{stage}-{name}.run.log",
    )
    runtime_stderr = safe_footer(runtime.stderr, 0, f"{stage}/{name}/run")
    if runtime.returncode != 0 or runtime_stderr:
        fail(f"{stage}/{name}: runtime failed or wrote to stderr")
    expected = str(case["expected"]).encode("utf-8")
    if runtime.stdout != expected:
        fail(f"{stage}/{name}: stdout mismatch; expected={expected!r}, actual={runtime.stdout!r}")


def check_negative(
    case: dict[str, object], stage: str, compiler: Path, safe_runner: Path,
    source: Path, work: Path, env: dict[str, str], link_flags: str,
) -> None:
    name = str(case["name"])
    output = work / f"{stage}-{name}.bin"
    cache = work / f"{stage}-{name}.cache"
    cache.mkdir()
    output.unlink(missing_ok=True)

    compile_env = env.copy()
    compile_env["CRYSTAL_CACHE_DIR"] = str(cache)
    if stage == "candidate":
        compile_env["ADAMAS_LLVM_CACHE"] = "0"
    command = [
        str(safe_runner), *compiler_command(stage, compiler, source, output, link_flags),
    ]
    result = execute(command, compile_env, work / f"{stage}-{name}.compile.log")
    safe_footer(result.stderr, 1, f"{stage}/{name}/compile")
    if result.returncode != 1:
        fail(f"{stage}/{name}: expected semantic compile exit 1, got {result.returncode}")
    if output.exists():
        fail(f"{stage}/{name}: rejected source left an executable")

    diagnostic = (result.stdout + result.stderr).decode(errors="replace")
    if ICE_RE.search(diagnostic):
        fail(f"{stage}/{name}: ICE/crash signature in rejection")
    if not re.search(r"(?im)^(?:error|Error)[:\[]", diagnostic):
        fail(f"{stage}/{name}: missing compiler error diagnostic")
    diagnostic_key = "candidate_diagnostic_regex" if stage == "candidate" else "stock_diagnostic_regex"
    pattern = re.compile(str(case[diagnostic_key]), re.MULTILINE)
    if not pattern.search(diagnostic):
        fail(f"{stage}/{name}: missing semantic diagnostic identity {pattern.pattern!r}")


def main() -> int:
    if len(sys.argv) > 3:
        fail("usage: callback_replay_contract_repro.sh [candidate]")
    root = Path(sys.argv[1]).resolve()
    positional_candidate = sys.argv[2] if len(sys.argv) == 3 else None

    script_dir = Path(__file__).resolve().parent
    fixture_root = script_dir / "fixtures" / "callback_replay_contract"
    manifest_path = fixture_root / "cases.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema") != "callback_replay_contract_cases_v1":
        fail("unsupported fixture manifest schema")
    cases = manifest.get("cases")
    if not isinstance(cases, list) or len(cases) != 20:
        fail("expected exactly 20 cases")
    names = [str(case.get("name")) for case in cases]
    if len(set(names)) != len(names):
        fail("duplicate fixture names")
    if sum(bool(case.get("ok")) for case in cases) != 16:
        fail("expected 16 positive and 4 negative cases")
    sources = {str(case["name"]): check_fixture_hash(case, fixture_root) for case in cases}
    if {path.stem for path in fixture_root.rglob("*.cr")} != set(names):
        fail("fixture files and case manifest do not match")

    safe_hint = os.environ.get("ADAMAS_SAFE_RUNNER", str(root / "scripts/run_safe.sh"))
    safe_runner = executable_path(safe_hint)
    original_hint = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
    original = executable_path(original_hint)
    original_only = os.environ.get("ORIGINAL_ONLY", "0") == "1"
    candidate_hint = positional_candidate or os.environ.get("ADAMAS_BIN", str(root / "bin/adamas"))
    candidate = Path(candidate_hint).resolve()
    if not safe_runner.is_file() or not os.access(safe_runner, os.X_OK):
        fail(f"missing safe runner: {safe_runner}")
    if not original.is_file() or not os.access(original, os.X_OK):
        fail(f"stock Crystal is not executable: {original}")
    if not original_only and (not candidate.is_file() or not os.access(candidate, os.X_OK)):
        fail(f"candidate compiler is not executable: {candidate}")

    work = Path(tempfile.mkdtemp(prefix="callback-replay-contract."))
    (work / "tmp").mkdir()
    (work / "home").mkdir()
    allowed_env = (
        "PATH", "LIBRARY_PATH", "ADAMAS_EXTRA_LINK_FLAGS", "ORIGINAL_CRYSTAL_LINK_FLAGS",
    )
    env = {key: os.environ[key] for key in allowed_env if key in os.environ}
    env.update(
        HOME=str(work / "home"),
        TMPDIR=str(work / "tmp"),
        LANG="C",
        LC_ALL="C",
        RUN_SAFE_PASSTHROUGH_STDIO="1",
        ADAMAS_LLVM_CACHE="0",
    )

    stdlib = os.environ.get("ORIGINAL_CRYSTAL_PATH") or os.environ.get("CRYSTAL_PATH")
    success = False
    try:
        if not stdlib:
            result = execute(
                [str(safe_runner), str(original), "20", "512", "env", "CRYSTAL_PATH"],
                env,
                work / "crystal-path.log",
            )
            prior = safe_footer(result.stderr, 0, "CRYSTAL_PATH lookup")
            if result.returncode != 0 or prior:
                fail("could not obtain CRYSTAL_PATH from stock Crystal")
            stdlib = result.stdout.decode().strip()
        if not stdlib or not any(Path(item).is_dir() for item in stdlib.split(os.pathsep)):
            fail("stock Crystal stdlib path is unavailable; set CRYSTAL_PATH")
        env["CRYSTAL_PATH"] = stdlib

        if sys.platform == "darwin":
            original_link_flags = env.get("ORIGINAL_CRYSTAL_LINK_FLAGS", "-fuse-ld=/usr/bin/ld")
        else:
            original_link_flags = env.get("ORIGINAL_CRYSTAL_LINK_FLAGS", "")
        candidate_link_flags = env.get("ADAMAS_EXTRA_LINK_FLAGS", "")
        stages = [("original", original, original_link_flags)]
        if not original_only:
            stages.append(("candidate", candidate, candidate_link_flags))

        for stage, compiler, link_flags in stages:
            for case in cases:
                source = sources[str(case["name"])]
                if case["ok"]:
                    check_positive(case, stage, compiler, safe_runner, source, work, env, link_flags)
                else:
                    check_negative(case, stage, compiler, safe_runner, source, work, env, link_flags)
                print(f"PASS[{stage}/{case['name']}]")
        success = True
        if original_only:
            print("PASS[stock-only]: all 20 fixtures match the available stock Crystal")
        else:
            print("PASS[callback-replay]: all 20 original-first cases agree")
        return 0
    finally:
        for cache in work.glob("*.cache"):
            shutil.rmtree(cache, ignore_errors=True)
        for binary in work.glob("*.bin"):
            binary.unlink(missing_ok=True)
        if success and os.environ.get("KEEP_ARTIFACTS") != "1":
            shutil.rmtree(work, ignore_errors=True)
        else:
            print(f"kept_artifacts={work}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
