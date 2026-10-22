#!/usr/bin/env python3
"""Strict original-first no-prelude oracle for source-backed macro block values."""
from __future__ import annotations
import ast
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PACKET = Path(__file__).resolve().parent
FIXTURES = PACKET / "fixtures"
POSITIVES = {
    'absent_callback_ast_shape': b'O',
    'empty_callback_body_ast_shape': b'P',
    'rest_argument_named_block_and_callback': b'R',
    'kwargs_argument_named_block_and_callback': b'S',
    "spawn_macro_block_single": b"D",
    "spawn_macro_block_multiple": b"FG",
    "ordinary_macro_block_single": b"E",
    "ordinary_argument_named_block_and_callback": b"H",
    "macro_without_block": b"N",
}
NEGATIVES = {
    "reject_ordinary_after_double_splat": b"after double splat",
    "reject_ordinary_after_double_splat_block": (b"expecting token ')', not ','", b"after double splat"),
    "spawn_macro_block_single_guard_negative": b"SpawnMacroBlockSingleBindingMustBePreserved",
    "spawn_macro_block_multiple_guard_negative": b"SpawnMacroBlockExpressionsBindingMustBePreserved",
    "ordinary_macro_block_named_guard_negative": b"OrdinaryMacroCallbackBindingMustBePreserved",
}
EXPECTED_FILES = {
    "fixtures/reject_ordinary_after_double_splat.cr",
    "fixtures/reject_ordinary_after_double_splat_block.cr",
    'fixtures/absent_callback_ast_shape.cr', 'fixtures/absent_callback_ast_shape.expected',
    'fixtures/empty_callback_body_ast_shape.cr', 'fixtures/empty_callback_body_ast_shape.expected',
    'fixtures/rest_argument_named_block_and_callback.cr', 'fixtures/rest_argument_named_block_and_callback.expected',
    'fixtures/kwargs_argument_named_block_and_callback.cr', 'fixtures/kwargs_argument_named_block_and_callback.expected',
    "README.md", "run_original_first.py", "run_original_first.sh",
    "fixtures/spawn_macro_block_single.cr", "fixtures/spawn_macro_block_single.expected",
    "fixtures/spawn_macro_block_multiple.cr", "fixtures/spawn_macro_block_multiple.expected",
    "fixtures/ordinary_macro_block_single.cr", "fixtures/ordinary_macro_block_single.expected",
    "fixtures/ordinary_argument_named_block_and_callback.cr",
    "fixtures/ordinary_argument_named_block_and_callback.expected",
    "fixtures/macro_without_block.cr", "fixtures/macro_without_block.expected",
    "fixtures/spawn_macro_block_single_guard_negative.cr",
    "fixtures/spawn_macro_block_multiple_guard_negative.cr",
    "fixtures/ordinary_macro_block_named_guard_negative.cr",
}
EXIT_RE = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE_RE = re.compile(rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=([0-9]+)(?: [A-Za-z0-9_.,:-]+=[A-Za-z0-9_.,:-]+)+\n")


def verify_callable_names() -> None:
    tree = ast.parse(Path(__file__).read_text())
    definitions = {node.name for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    prefixes = ("verify_", "compile_", "run_", "check_", "stage_", "safe_", "self_test_")
    undefined = sorted({node.func.id for node in ast.walk(tree)
                        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                        and node.func.id.startswith(prefixes) and node.func.id not in definitions})
    if undefined:
        raise RuntimeError(f"undefined local helper calls: {undefined}")


def verify_packet() -> None:
    actual = {p.relative_to(PACKET).as_posix() for p in PACKET.rglob("*") if p.is_file() and p.name != "artifact_manifest.json"}
    if actual != EXPECTED_FILES:
        raise RuntimeError(f"packet inventory mismatch: extra={sorted(actual - EXPECTED_FILES)} missing={sorted(EXPECTED_FILES - actual)}")
    manifest = json.loads((PACKET / "artifact_manifest.json").read_text())
    if set(manifest.get("files", {})) != EXPECTED_FILES:
        raise RuntimeError("artifact manifest inventory mismatch")
    for relative, expected_sha in manifest["files"].items():
        actual_sha = hashlib.sha256((PACKET / relative).read_bytes()).hexdigest()
        if actual_sha != expected_sha:
            raise RuntimeError(f"artifact hash mismatch: {relative}")
    expected_fixtures = {Path(name).name for name in EXPECTED_FILES if name.startswith("fixtures/")}
    actual_fixtures = {p.name for p in FIXTURES.iterdir() if p.is_file()}
    if expected_fixtures != actual_fixtures:
        raise RuntimeError("fixture inventory mismatch")
    if not os.access(PACKET / "run_original_first.py", os.X_OK) or not os.access(PACKET / "run_original_first.sh", os.X_OK):
        raise RuntimeError("runner executable bit missing")
    verify_callable_names()


def safe_footer(raw: bytes, expected: int) -> tuple[bytes, bytes]:
    """Validate run_safe framing and return captured child stdout/stderr."""
    lines = raw.splitlines(keepends=True)
    exits = [i for i, line in enumerate(lines) if line.startswith(b"[EXIT: ")]
    resources = [i for i, line in enumerate(lines) if line.startswith(b"[RUN_SAFE_RESOURCE] ")]
    if len(exits) != 1 or len(resources) != 1 or exits[0] != len(lines) - 2 or resources[0] != len(lines) - 1:
        raise RuntimeError("missing or misplaced run_safe footer pair")
    exit_match, resource_match = EXIT_RE.fullmatch(lines[-2]), RESOURCE_RE.fullmatch(lines[-1])
    if not exit_match or not resource_match or int(exit_match.group(1)) != expected or int(resource_match.group(1)) != expected:
        raise RuntimeError("run_safe status footer mismatch")

    body = lines[:-2]
    stdout_header = b"=== STDOUT ===\n"
    stderr_header = b"=== STDERR ===\n"
    if not body:
        return b"", b""
    stdout_positions = [i for i, line in enumerate(body) if line == stdout_header]
    stderr_positions = [i for i, line in enumerate(body) if line == stderr_header]
    if stdout_positions or stderr_positions:
        if stdout_positions == [0] and len(stderr_positions) == 1 and stderr_positions[0] > 0:
            split = stderr_positions[0]
            return b"".join(body[1:split]), b"".join(body[split + 1:])
        # RUN_SAFE_PASSTHROUGH_STDIO=1 omits the stdout wrapper and only
        # emits a stderr section when the child actually wrote stderr.
        if not stdout_positions and stderr_positions == [0]:
            return b"", b"".join(body[1:])
        raise RuntimeError("malformed run_safe stdout/stderr sections")

    # In passthrough mode child stderr may immediately precede the footer.
    return b"", b"".join(body)


def self_test_safe_footer() -> None:
    def frame(code: int, body: bytes) -> bytes:
        return (body
                + f"[EXIT: {code}] after ~0s\n".encode()
                + f"[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code={code} rss_kb=1 fd_count=1\n".encode())

    compile_empty = frame(0, b"=== STDOUT ===\n=== STDERR ===\n")
    if safe_footer(compile_empty, 0) != (b"", b""):
        raise RuntimeError("run_safe empty compile sections were not accepted")
    compile_diagnostic = frame(1, b"=== STDOUT ===\ncompiler line\n=== STDERR ===\nEXPECTED_MARKER\n")
    if safe_footer(compile_diagnostic, 1) != (b"compiler line\n", b"EXPECTED_MARKER\n"):
        raise RuntimeError("run_safe diagnostic sections were not preserved")
    passthrough_stderr_section = frame(0, b"=== STDERR ===\nchild stderr\n")
    if safe_footer(passthrough_stderr_section, 0) != (b"", b"child stderr\n"):
        raise RuntimeError("run_safe passthrough stderr section was not parsed")
    if safe_footer(frame(0, b""), 0) != (b"", b""):
        raise RuntimeError("run_safe passthrough footer-only output was not accepted")
    if safe_footer(frame(0, b"child stderr\n"), 0) != (b"", b"child stderr\n"):
        raise RuntimeError("run_safe passthrough stderr was not preserved")

    malformed = (
        frame(0, b"prefix before stderr header\n=== STDERR ===\nmissing stdout header\n"),
        frame(0, b"=== STDOUT ===\n=== STDERR ===\n=== STDERR ===\n"),
        b"=== STDOUT ===\n=== STDERR ===\n[EXIT: 0] after ~0s\n",
    )
    for raw in malformed:
        try:
            safe_footer(raw, 0)
        except RuntimeError:
            pass
        else:
            raise RuntimeError("malformed run_safe capture was accepted")


def compile_case(stage: str, compiler: Path, name: str, work: Path, safe: Path, original: bool):
    source = FIXTURES / f"{name}.cr"
    binary = work / f"{stage}.{name}.program"
    cache = work / f"cache.{stage}.{name}"
    shutil.rmtree(cache, ignore_errors=True)
    cache.mkdir()
    binary.unlink(missing_ok=True)
    env = os.environ.copy()
    env["CRYSTAL_CACHE_DIR"] = str(cache)
    timeout = int(env.get("MACRO_BLOCK_COMPILE_TIMEOUT_SEC", "120"))
    memory = env.get("MACRO_BLOCK_COMPILE_MAX_MEM_MB", "8192")
    if original:
        args = ["build", "--no-debug", "--prelude=empty"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
    else:
        env["ADAMAS_LLVM_CACHE"] = "0"
        args = ["--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache"]
    result = subprocess.run([str(safe), str(compiler), str(timeout), str(memory), *args, str(source), "-o", str(binary)],
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout + 15)
    log = work / f"{stage}.{name}.compile.log"
    log.write_bytes(result.stdout)
    shutil.rmtree(cache, ignore_errors=True)
    return binary, result.returncode, result.stdout, log


def run_positive(stage: str, compiler: Path, name: str, expected: bytes, work: Path, safe: Path, original: bool) -> None:
    binary, status, raw, log = compile_case(stage, compiler, name, work, safe, original)
    if status != 0 or not binary.is_file():
        raise RuntimeError(f"compile failed status={status}; log={log}")
    compile_stdout, compile_stderr = safe_footer(raw, 0)
    # The current compiler emits these bootstrap instrumentation records even
    # without debug_hooks. Permit only the exact known record grammar during
    # compilation; diagnostics and all runtime stderr remain forbidden.
    if not original:
        trace = re.compile(rb"\[STAGE2_TRACE\] lower_main: (?:start, lazy=(?:true|false)|lazy classvar recording [0-9]+ inits|lazy const sorting [0-9]+ inits|lazy const sorted, processing|deferred processing done|about to setup debug vars|debug_main=(?:true|false) slow_only=(?:true|false)|exprs=[0-9]+)\n")
        compile_stderr = b"".join(line for line in compile_stderr.splitlines(keepends=True) if not trace.fullmatch(line))
    if compile_stdout or compile_stderr:
        raise RuntimeError(f"unexpected successful compile output: stdout={compile_stdout!r} stderr={compile_stderr!r}; log={log}")
    env = os.environ.copy()
    env["RUN_SAFE_PASSTHROUGH_STDIO"] = "1"
    result = subprocess.run([str(safe), str(binary), "5", "512"], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    run_log = work / f"{stage}.{name}.run.log"
    run_log.write_bytes(b"STDOUT\n" + result.stdout + b"\nSTDERR\n" + result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"run status={result.returncode}; stderr={result.stderr!r}; log={run_log}")
    _, runtime_stderr = safe_footer(result.stderr, 0)
    if runtime_stderr:
        raise RuntimeError(f"unexpected runtime stderr: {runtime_stderr!r}; log={run_log}")
    if result.stdout != expected:
        raise RuntimeError(f"stdout={result.stdout!r}, expected={expected!r}; log={run_log}")
    binary.unlink(missing_ok=True)
    print(f"PASS[{stage}:{name}] stdout={result.stdout!r}", flush=True)


def run_negative(stage: str, compiler: Path, name: str, marker: bytes, work: Path, safe: Path, original: bool) -> None:
    binary, status, raw, log = compile_case(stage, compiler, name, work, safe, original)
    if status != 1 or binary.exists() or marker not in raw:
        raise RuntimeError(f"expected compile-time marker {marker!r}; status={status}; log={log}")
    compile_stdout, compile_stderr = safe_footer(raw, 1)
    if marker not in compile_stdout + compile_stderr:
        raise RuntimeError(f"expected marker outside run_safe sections; marker={marker!r}; log={log}")
    print(f"PASS[{stage}:{name}] marker={marker.decode()}", flush=True)


def stage(compiler: Path, work: Path, safe: Path, original: bool) -> None:
    label = "original" if original else "candidate"
    for name, expected in POSITIVES.items():
        run_positive(label, compiler, name, expected, work, safe, original)
    for name, marker in NEGATIVES.items():
        run_negative(label, compiler, name, (marker[0 if original else 1] if isinstance(marker, tuple) else marker), work, safe, original)
    print(f"{label.upper()}_PASS_COMPLETE[macro_block_provider_wiring]", flush=True)


def main() -> int:
    verify_packet()
    if sys.argv[1:] == ["--self-test"]:
        self_test_safe_footer()
        print("PASS[static inventory, hashes, executable mode, helper-call audit, and canned run_safe captures]", flush=True)
        return 0
    original_text = os.environ.get("CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL")
    candidate_text = os.environ.get("ADAMAS_BIN") or (sys.argv[1] if len(sys.argv) == 2 else None)
    if not original_text:
        raise SystemExit("set CRYSTAL_BIN to the pinned original Crystal compiler")
    if len(sys.argv) > 2:
        raise SystemExit("usage: run_original_first.sh [candidate-adamas-bin]")
    original = Path(original_text).resolve()
    candidate = Path(candidate_text).resolve() if candidate_text else None
    safe = Path(os.environ.get("ADAMAS_RUN_SAFE", str(PACKET.parents[1] / "scripts/run_safe.sh"))).resolve()
    if not original.is_file() or not os.access(original, os.X_OK) or not safe.is_file() or not os.access(safe, os.X_OK):
        raise SystemExit("missing executable pinned Crystal or run_safe.sh")
    if candidate and (not candidate.is_file() or not os.access(candidate, os.X_OK)):
        raise SystemExit("candidate compiler is not executable")
    output_text = os.environ.get("MACRO_BLOCK_OUTPUT_DIR")
    if not output_text:
        raise SystemExit("set MACRO_BLOCK_OUTPUT_DIR to a fresh absolute directory outside this packet")
    work = Path(output_text).resolve()
    if not work.is_absolute() or work.exists() or work == PACKET or PACKET in work.parents:
        raise SystemExit("output directory must be fresh, absolute, and outside the packet")
    work.mkdir(parents=True)
    print(f"ORACLE_OUTPUT_DIR[{work}]", flush=True)
    success = False
    try:
        stage(original, work, safe, True)
        if candidate:
            stage(candidate, work, safe, False)
        success = True
    finally:
        for binary in work.glob("*.program*"):
            if binary.is_file() and not binary.is_symlink():
                binary.unlink()
        for cache in work.glob("cache.*"):
            if cache.is_dir() and not cache.is_symlink():
                shutil.rmtree(cache)
        if not success:
            print(f"kept_logs={work}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
