#!/usr/bin/env python3
"""Compile-only original-first oracle for FFI out declaration scope."""

from pathlib import Path
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile


PACKET = Path(__file__).resolve().parent
FIXTURES = PACKET / "fixtures"
REPOSITORY = Path(os.environ.get("ADAMAS_ROOT", str(PACKET.parents[1]))).resolve()
DEFAULT_ORIGINAL = Path(shutil.which("crystal") or "crystal")
DEFAULT_CRYSTAL_PATH = Path(
    os.environ.get("CRYSTAL_PATH", str(REPOSITORY.parent / "crystal/src"))
)

POSITIVES = [
    "condition_out_visible_in_both_arms",
    "sibling_block_declarations_are_isolated",
    "block_declaration_does_not_escape",
]
NEGATIVES = [
    "sibling_dynamic_branches_reject_duplicate",
    "repeated_out_inside_one_block",
    "nested_block_rejects_outer_out_name",
    "reject_repeated",
    "reject_preexisting",
]

EXIT_LINE = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE_LINE = re.compile(
    rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit "
    rb"exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n"
)
NON_SEMANTIC = re.compile(
    r"(?i)(syntax error|unexpected token|unterminated|invalid syntax|"
    r"internal compiler error|unhandled exception|stack overflow)"
)


def safe_footer(raw: bytes, expected: int) -> bytes:
    """Validate the terminal run_safe pair while allowing captured headers/logs."""
    lines = raw.splitlines(keepends=True)
    exits = [index for index, line in enumerate(lines) if line.startswith(b"[EXIT: ")]
    resources = [
        index for index, line in enumerate(lines)
        if line.startswith(b"[RUN_SAFE_RESOURCE] ")
    ]
    if len(exits) != 1 or len(resources) != 1:
        raise AssertionError("expected exactly one run_safe footer pair")
    if exits[0] != len(lines) - 2 or resources[0] != len(lines) - 1:
        raise AssertionError("run_safe footer pair must be the final two lines")
    if resources[0] != exits[0] + 1:
        raise AssertionError("run_safe footer records must be adjacent")
    exit_match = EXIT_LINE.fullmatch(lines[-2])
    resource_match = RESOURCE_LINE.fullmatch(lines[-1])
    if not exit_match or not resource_match:
        raise AssertionError("malformed run_safe footer")
    if int(exit_match.group(1)) != expected or int(resource_match.group(1)) != expected:
        raise AssertionError("run_safe footer status mismatch")
    return lines[-2] + lines[-1]


def primary_diagnostic(raw: bytes) -> bytes:
    """Return the first substantive Crystal Error line, skipping known wrappers."""
    for line in raw.decode(errors="replace").splitlines():
        stripped = line.strip()
        if re.match(r"(?i)^error:\s*instantiating\b", stripped):
            continue
        if re.match(r"(?i)^error\s+while\s+requiring\b", stripped):
            continue
        if re.match(r"(?i)^error:\s*while\s+requiring\b", stripped):
            continue
        if re.match(r"(?i)^error:", stripped):
            return stripped.encode()
    return b""


def packet_sums() -> None:
    sums_path = PACKET / "SHA256SUMS"
    if not sums_path.is_file():
        raise RuntimeError("packet SHA256SUMS is missing")
    expected = {}
    for line in sums_path.read_text().splitlines():
        digest, relative = line.split("  ", 1)
        path = (PACKET / relative).resolve()
        if PACKET.resolve() not in path.parents:
            raise RuntimeError(f"checksum path escapes packet: {relative}")
        expected[relative] = digest
    actual_paths = {
        path.relative_to(PACKET).as_posix()
        for path in PACKET.rglob("*")
        if path.is_file() and path != sums_path
    }
    if actual_paths != set(expected):
        raise RuntimeError(
            f"packet closure mismatch: missing={sorted(actual_paths - set(expected))}, "
            f"unexpected={sorted(set(expected) - actual_paths)}"
        )
    for relative, digest in expected.items():
        actual = hashlib.sha256((PACKET / relative).read_bytes()).hexdigest()
        if actual != digest:
            raise RuntimeError(f"packet checksum mismatch: {relative}")


def _self_test() -> None:
    valid_footer = (
        b"=== STDOUT ===\ncompiler output\n=== STDERR ===\n"
        b"[EXIT: 0] after ~0.2s\n"
        b"[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit "
        b"exit_code=0 max_rss_kb=unknown max_fd=unknown rss_samples=0 fd_samples=0 "
        b"rss_available=unknown fd_available=unknown process_tree_mode=unknown "
        b"tree_coverage=unknown fd_tree_coverage=unknown tree_samples=0 "
        b"fd_topology_stable_samples=0 fd_topology_unstable_samples=0 max_tree_pids=0\n"
    )
    safe_footer(valid_footer, 0)
    negative_footer = valid_footer.replace(
        b"[EXIT: 0]", b"[EXIT: 1]", 1
    ).replace(b"exit_code=0", b"exit_code=1", 1)
    safe_footer(negative_footer, 1)
    for invalid in (
        valid_footer + b"trailing noise\n",
        valid_footer.replace(b"max_rss_kb=unknown", b"max_rss_kb=", 1),
        valid_footer.replace(b"[EXIT: 0]", b"[EXIT: 9]", 1),
        valid_footer + b"[EXIT: 0] after ~0.2s\n",
        valid_footer.replace(b"outcome=exit reason=exit", b"outcome=timeout reason=timeout", 1),
    ):
        try:
            safe_footer(invalid, 0)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"invalid footer accepted: {invalid!r}")

    cases = (
        (
            b"Error: instantiating 'f(T)\nError: variable 'branch_end' is already defined\n",
            b"Error: variable 'branch_end' is already defined",
        ),
        (
            b"Error: while requiring ./dep\nError: variable 'tail' is already defined\n",
            b"Error: variable 'tail' is already defined",
        ),
        (
            b"Error: unexpected token: 'else'\nError: variable 'tail' is already defined\n",
            b"Error: unexpected token: 'else'",
        ),
        (
            b"Error: internal compiler error: bad HIR\nError: variable 'tail' is already defined\n",
            b"Error: internal compiler error: bad HIR",
        ),
    )
    for raw, expected in cases:
        actual = primary_diagnostic(raw)
        if actual != expected:
            raise AssertionError((raw, actual, expected))
    for _, diagnostic in cases[2:]:
        if not NON_SEMANTIC.search(diagnostic.decode()):
            raise AssertionError(f"nonsemantic self-test malformed: {diagnostic!r}")
    fixture_stems = {path.stem for path in FIXTURES.glob("*.cr")}
    if fixture_stems != set(POSITIVES + NEGATIVES):
        raise AssertionError(f"fixture matrix mismatch: {fixture_stems!r}")
    for name in NEGATIVES:
        for stage in ("original", "candidate"):
            expectation = FIXTURES / f"{name}.{stage}.reject"
            if not expectation.is_file() or not expectation.read_text().strip():
                raise AssertionError(f"missing stage-specific negative expectation: {expectation.name}")
    packet_sums()


def _safe_runner() -> Path:
    configured = os.environ.get("ADAMAS_RUN_SAFE")
    if configured:
        return Path(configured).resolve()
    root = os.environ.get("ADAMAS_ROOT")
    if root:
        return Path(root).resolve() / "scripts/run_safe.sh"
    cwd_default = Path.cwd() / "scripts/run_safe.sh"
    if cwd_default.is_file():
        return cwd_default.resolve()
    raise RuntimeError("set ADAMAS_RUN_SAFE to the repository scripts/run_safe.sh")


def _resolve_original() -> Path:
    configured = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL")
    if configured:
        found = shutil.which(configured)
        return Path(found or configured).resolve()
    return DEFAULT_ORIGINAL.resolve()


def _compile(stage: str, host: Path, name: str, work: Path, safe: Path, crystal_path: Path):
    fixture = FIXTURES / f"{name}.cr"
    binary = work / f"{stage}.{name}.program"
    cache = work / f"{stage}.{name}.cache"
    if binary.exists():
        binary.unlink()
    shutil.rmtree(cache, ignore_errors=True)
    cache.mkdir()
    env = os.environ.copy()
    env["CRYSTAL_CACHE_DIR"] = str(cache)
    env["CRYSTAL_PATH"] = str(crystal_path)
    env["RUN_SAFE_PASSTHROUGH_STDIO"] = "0"
    env.pop("RUN_SAFE_RESOURCE_FILE", None)
    if stage == "original":
        args = ["build", "--no-debug", "--error-trace", "--prelude=empty"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        args.extend([str(fixture), "-o", str(binary)])
    else:
        env["ADAMAS_LLVM_CACHE"] = "0"
        args = [
            str(fixture), "--no-prelude", "--no-debug", "--no-ast-cache",
            "--no-llvm-cache", "-o", str(binary),
        ]
    result = subprocess.run(
        [str(safe), str(host), "60", "2048", *args],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=75,
    )
    log = work / f"{stage}.{name}.compile.log"
    log.write_bytes(result.stdout)
    shutil.rmtree(cache, ignore_errors=True)
    return binary, result, log


def _positive(stage: str, host: Path, name: str, work: Path, safe: Path, crystal_path: Path):
    binary, result, log = _compile(stage, host, name, work, safe, crystal_path)
    raw = log.read_bytes()
    if result.returncode != 0:
        raise RuntimeError(f"{stage}:{name} expected compile success, got {result.returncode}: {raw!r}")
    safe_footer(raw, 0)
    if not binary.is_file():
        raise RuntimeError(f"{stage}:{name} successful compile produced no executable")
    binary.unlink()
    print(f"PASS[{stage}:{name}] compile-only", flush=True)


def _negative(stage: str, host: Path, name: str, work: Path, safe: Path, crystal_path: Path):
    binary, result, log = _compile(stage, host, name, work, safe, crystal_path)
    raw = log.read_bytes()
    if result.returncode != 1:
        raise RuntimeError(f"{stage}:{name} expected compile rejection status 1, got {result.returncode}: {raw!r}")
    if binary.exists():
        raise RuntimeError(f"{stage}:{name} rejection left an executable")
    safe_footer(raw, 1)
    primary = primary_diagnostic(raw)
    if not primary:
        raise RuntimeError(f"{stage}:{name} has no primary compiler diagnostic: {raw!r}")
    if NON_SEMANTIC.search(primary.decode(errors="replace")):
        raise RuntimeError(f"{stage}:{name} failed for parser/internal error: {primary!r}")
    expected = (FIXTURES / f"{name}.{stage}.reject").read_text().strip()
    if expected.encode() not in primary:
        raise RuntimeError(f"{stage}:{name} primary diagnostic {primary!r} misses {expected!r}")
    print(f"PASS[{stage}:{name}] rejected by {primary.decode(errors='replace')}", flush=True)


def _collect(stage: str, host: Path, work: Path, safe: Path, crystal_path: Path):
    failures = []
    for name in POSITIVES:
        try:
            _positive(stage, host, name, work, safe, crystal_path)
        except Exception as exc:
            failures.append(f"{name}: {exc}")
            print(f"FAIL[{stage}:{name}] {exc}", flush=True)
    for name in NEGATIVES:
        try:
            _negative(stage, host, name, work, safe, crystal_path)
        except Exception as exc:
            failures.append(f"{name}: {exc}")
            print(f"FAIL[{stage}:{name}] {exc}", flush=True)
    return failures


def main():
    if sys.argv[1:] == ["--self-test"]:
        _self_test()
        print("PASS packet closure, footer, primary-diagnostic self-tests", flush=True)
        return
    _self_test()
    if len(sys.argv) != 2:
        raise SystemExit("usage: run_original_first.sh CANDIDATE_HOST")
    candidate = Path(sys.argv[1]).resolve()
    original = _resolve_original()
    crystal_path = Path(os.environ.get("ORIGINAL_CRYSTAL_PATH", str(DEFAULT_CRYSTAL_PATH))).resolve()
    safe = _safe_runner()
    for path, name in ((candidate, "candidate compiler"), (original, "pinned original compiler"),
                       (crystal_path, "pinned Crystal source tree"), (safe, "safe runner")):
        if not path.exists():
            raise RuntimeError(f"{name} does not exist: {path}")
    if not os.access(safe, os.X_OK):
        raise RuntimeError(f"safe runner is not executable: {safe}")
    fixture_stems = {path.stem for path in FIXTURES.glob("*.cr")}
    if fixture_stems != set(POSITIVES + NEGATIVES):
        raise RuntimeError(f"fixture matrix mismatch: {fixture_stems!r}")
    work = Path(tempfile.mkdtemp(prefix="adamas_ffi_out_lexical_scope_"))
    success = False
    try:
        original_failures = _collect("original", original, work, safe, crystal_path)
        if original_failures:
            raise RuntimeError(f"original-first gate failed: {original_failures!r}")
        candidate_failures = _collect("candidate", candidate, work, safe, crystal_path)
        if candidate_failures:
            raise RuntimeError(f"candidate stage failed: {candidate_failures!r}")
        success = True
        print("PASS original-first FFI out scope matrix", flush=True)
    finally:
        for path in work.glob("*.cache"):
            shutil.rmtree(path, ignore_errors=True)
        for path in work.glob("*.program"):
            path.unlink(missing_ok=True)
        if success and os.environ.get("KEEP_ARTIFACTS") != "1":
            shutil.rmtree(work, ignore_errors=True)
        else:
            print(f"kept_compile_logs={work}", file=sys.stderr)


if __name__ == "__main__":
    main()
