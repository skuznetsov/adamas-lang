#!/usr/bin/env python3
"""Original-first source-kind body demand regression packet.

--self-test validates only local packet files and never invokes a compiler.
"""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures"
MANIFEST = HERE / "cases.json"
POSITIVE = ('bare_nullable_sync', 'without_binding_capture', 'explicit_value_call', 'annotated_value_method', 'prematerialized_value', 'populated_cache_runtime_once', 'primitive_bodyful_sibling', 'primitive_empty_sibling')
NEGATIVE = ('reject_class_valued_value',)
CASES = POSITIVE + NEGATIVE
EXPECTED = {'bare_nullable_sync': b'G\n', 'without_binding_capture': b'H\n', 'explicit_value_call': b'I\n', 'annotated_value_method': b'J\n', 'prematerialized_value': b'K\n', 'populated_cache_runtime_once': b'VM\n', 'primitive_bodyful_sibling': b'A\n', 'primitive_empty_sibling': b'A\n'}
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(
    rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit "
    rb"exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n"
)
BAD_REJECTION = (
    b"parse error", b"sigsegv", b"stack overflow", b"segmentation fault",
    b"failed to emit", b"could not emit", b"unable to emit", b"failed to write executable",
    b"llvm error", b"bus error", b"unhandled exception", b"compiler bug",
)


def find_root():
    configured = os.environ.get("ADAMAS_ROOT")
    if configured:
        root = Path(configured).resolve()
        assert (root / "scripts/run_safe.sh").is_file(), root
        return root
    for parent in HERE.parents:
        if (parent / "scripts/run_safe.sh").is_file():
            return parent
        sibling = parent / "adamas"
        if (sibling / "scripts/run_safe.sh").is_file():
            return sibling
    raise RuntimeError("set ADAMAS_ROOT to the Adamas checkout")


def footer(raw: bytes, expected: int) -> bytes:
    lines = raw.splitlines(keepends=True)
    assert len(lines) >= 2, "missing run_safe footer"
    assert sum(line.startswith(b"[EXIT: ") for line in lines) == 1
    assert sum(line.startswith(b"[RUN_SAFE_RESOURCE] ") for line in lines) == 1
    exit_match = EXIT.fullmatch(lines[-2])
    resource_match = RESOURCE.fullmatch(lines[-1])
    assert exit_match and resource_match, "malformed run_safe footer"
    assert int(exit_match[1]) == expected and int(resource_match[1]) == expected
    return lines[-2] + lines[-1]


def rejection_markers(label: str, case: str) -> tuple[bytes, ...]:
    diagnostic_label = "original" if label == "original" else "candidate"
    path = FIXTURES / f"{case}.{diagnostic_label}.reject"
    markers = tuple(line.strip() for line in path.read_bytes().splitlines() if line.strip())
    assert markers, f"{path} has no semantic rejection markers"
    return markers


def check_rejection(label: str, case: str, raw: bytes):
    lowered = raw.lower()
    markers = rejection_markers(label, case)
    assert any(marker.lower() in lowered for marker in markers), (
        f"{label}:{case} missing semantic diagnostic alternatives {markers!r}: {raw!r}"
    )
    assert not any(marker in lowered for marker in BAD_REJECTION), raw
    assert b"error:" in lowered, raw


def self_test():
    sample_footer = (
        b"compile output\n[EXIT: 0] after ~0.01s\n"
        b"[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit "
        b"exit_code=0 elapsed_ms=10 max_rss_kb=100 fd_count=4\n"
    )
    assert footer(sample_footer, 0) == (
        b"[EXIT: 0] after ~0.01s\n" + sample_footer.splitlines(keepends=True)[-1]
    )
    assert len(CASES) == len(set(CASES))
    assert {path.stem for path in FIXTURES.glob("*.cr")} == set(CASES)
    assert {path.stem for path in FIXTURES.glob("*.expected")} == set(POSITIVE)
    manifest = json.loads(MANIFEST.read_text())
    assert {item["name"] for item in manifest} == set(CASES)
    for item in manifest:
        name = item["name"]
        assert Path(item["source"]).name == f"{name}.cr"
        assert item["ok"] is (name in POSITIVE)
        assert item["expected"] == EXPECTED.get(name, b"").decode()
    for case, expected in EXPECTED.items():
        assert (FIXTURES / f"{case}.expected").read_bytes() == expected
    for case in NEGATIVE:
        for label in ("original", "candidate"):
            for marker in rejection_markers(label, case):
                check_rejection(label, case, b"error: " + marker + b"\n")
                check_rejection(label, case, b"ERROR: " + marker + b"\n")
                for bad in BAD_REJECTION:
                    try:
                        check_rejection(label, case, b"error: " + marker + b"\n" + bad + b"\n")
                    except AssertionError:
                        pass
                    else:
                        raise AssertionError(f"accepted false-positive marker {bad!r}")
            try:
                check_rejection(label, case, b"error: unrelated undefined constant\n")
            except AssertionError:
                pass
            else:
                raise AssertionError(f"accepted unrelated error for {label}:{case}")
    print(f"PASS packet self-test: {len(POSITIVE)} positives, {len(NEGATIVE)} negatives; no compiler invoked")


def run_case(label: str, compiler: Path, case: str, work: Path, safe: Path):
    source = FIXTURES / f"{case}.cr"
    binary = work / f"{label}.{case}.program"
    cache = work / f"{label}.{case}.cache"
    cache.mkdir()
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("ADAMAS_", "DEBUG_", "RUN_SAFE_"))}
    env.update(CRYSTAL_CACHE_DIR=str(cache), ADAMAS_LLVM_CACHE="0")
    if label == "candidate_eager":
        env["ADAMAS_EAGER_MONO"] = "1"
    if label == "original":
        args = ["build", "--no-debug", "--prelude=empty"]
        if sys.platform == "darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        args += [str(source), "-o", str(binary)]
    else:
        args = [
            str(source), "--no-prelude", "--no-debug", "--no-ast-cache",
            "--no-llvm-cache", "-o", str(binary),
        ]
    result = subprocess.run(
        [str(safe), str(compiler), "120", "4096", *args], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145,
    )
    (work / f"{label}.{case}.compile.log").write_bytes(result.stdout)
    positive = case in POSITIVE
    expected_status = 0 if positive else 1
    assert result.returncode == expected_status, (
        f"{label}:{case} compile rc={result.returncode}: {result.stdout!r}"
    )
    footer(result.stdout, expected_status)
    if not positive:
        assert not binary.exists(), f"{label}:{case} emitted an executable despite rejection"
        check_rejection(label, case, result.stdout)
        print(f"PASS[{label}:{case}] semantic diagnostic", flush=True)
        return
    assert binary.is_file(), f"{label}:{case} failed to emit executable"
    runtime = subprocess.run(
        [str(safe), str(binary), "5", "512"],
        env={**env, "RUN_SAFE_PASSTHROUGH_STDIO": "1"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
    )
    (work / f"{label}.{case}.stdout").write_bytes(runtime.stdout)
    (work / f"{label}.{case}.stderr").write_bytes(runtime.stderr)
    assert runtime.returncode == 0, f"{label}:{case} runtime rc={runtime.returncode}"
    assert runtime.stderr == footer(runtime.stderr, 0), runtime.stderr
    expected = (FIXTURES / f"{case}.expected").read_bytes()
    assert runtime.stdout == expected, f"{label}:{case} stdout={runtime.stdout!r}, expected={expected!r}"
    print(f"PASS[{label}:{case}] stdout={runtime.stdout!r}", flush=True)


def main():
    args = sys.argv[1:]
    if args == ["--self-test"]:
        self_test()
        return
    original_only = args == ["--original-only"]
    assert original_only or len(args) == 1, "usage: run.py --self-test | --original-only | candidate-adamas"
    root = find_root()
    safe = Path(os.environ.get("ADAMAS_RUN_SAFE", str(root / "scripts/run_safe.sh"))).resolve()
    original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
    original = Path(shutil.which(original_name) or original_name).resolve()
    candidate = None if original_only else Path(args[0]).resolve()
    assert safe.is_file() and os.access(safe, os.X_OK), safe
    assert original.is_file() and os.access(original, os.X_OK), original
    if candidate:
        assert candidate.is_file() and os.access(candidate, os.X_OK), candidate

    output = os.environ.get("SOURCE_KIND_BODY_DEMAND_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists(), work
        work.mkdir()
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_source_kind_body_demand_"))
    try:
        # Candidate checks begin only after every stock control passes.
        for label, compiler in (("original", original), ("candidate", candidate), ("candidate_eager", candidate)):
            if compiler is None:
                continue
            failures = []
            for case in CASES:
                try:
                    run_case(label, compiler, case, work, safe)
                except Exception as exc:
                    failures.append((case, str(exc)))
                    print(f"FAIL[{label}:{case}] {exc}", flush=True)
            assert not failures, f"{label} failures: {failures}"
            print(f"{label.upper()}_PASS_COMPLETE[source_kind_body_demand]", flush=True)
    finally:
        for binary in work.glob("*.program"):
            binary.unlink()
        for cache in work.glob("*.cache"):
            shutil.rmtree(cache)
        print("kept_logs=" + str(work), file=sys.stderr)


if __name__ == "__main__":
    main()
