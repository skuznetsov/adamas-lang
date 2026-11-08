#!/usr/bin/env python3
"""Stock-first native oracle for completed callback member source results."""
from pathlib import Path
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
FIXTURES = HERE
POSITIVE = ('instance', 'local_alias', 'side_effect', 'transitive', 'constructed', 'class_result', 'annotated_child', 'annotated_int', 'builtin_string', 'builtin_int')
NEGATIVE = ('reject_instance_as_class', 'reject_class_as_instance', 'reject_invalid_return')
CASES = POSITIVE + NEGATIVE
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(
    rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit "
    rb"exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n"
)
BAD_REJECTION = (
    b"parse error", b"syntax error", b"sigsegv", b"stack overflow",
    b"segmentation fault", b"failed to emit", b"could not emit",
    b"unable to emit", b"llvm error", b"bus error", b"unhandled exception",
    b"compiler bug", b"timed out", b"resource limit",
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


def check_rejection(case: str, raw: bytes):
    lowered = raw.lower()
    markers = tuple(
        line.strip().lower()
        for line in (FIXTURES / f"{case}.reject").read_bytes().splitlines()
        if line.strip()
    )
    assert all(marker in lowered for marker in markers), (
        f"{case} missing member-result diagnostic markers {markers!r}: {raw!r}"
    )
    assert b"error:" in lowered, raw
    assert not any(marker in lowered for marker in BAD_REJECTION), raw


def compiler_command(label: str, compiler: Path, source: Path, binary: Path):
    if label == "original":
        args = ["build", "--prelude=empty", "--no-debug", str(source), "-o", str(binary)]
        if platform.system() == "Darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        return args
    return [
        str(source), "--no-prelude", "--no-debug",
        "--no-ast-cache", "--no-llvm-cache", "-o", str(binary),
    ]


def run_case(label: str, compiler: Path, case: str, work: Path, safe: Path):
    source = FIXTURES / f"{case}.cr"
    binary = work / f"{label}.{case}.program"
    cache = work / f"{label}.{case}.cache"
    cache.mkdir()
    env = {**os.environ, "CRYSTAL_CACHE_DIR": str(cache), "ADAMAS_LLVM_CACHE": "0"}
    if label == "candidate-lazy":
        env.pop("ADAMAS_EAGER_HIR", None)
        env.pop("ADAMAS_EAGER_MONO", None)
    elif label == "candidate-eager":
        env["ADAMAS_EAGER_HIR"] = "1"
        env["ADAMAS_EAGER_MONO"] = "1"
    if label.startswith("candidate") and platform.system() == "Darwin":
        env["ADAMAS_EXTRA_LINK_FLAGS"] = os.environ.get("ADAMAS_EXTRA_LINK_FLAGS", "-fuse-ld=/usr/bin/ld")
    result = subprocess.run(
        [str(safe), str(compiler), "120", "4096", *compiler_command(label.split("-")[0] if label == "original" else "candidate", compiler, source, binary)],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145,
    )
    (work / f"{label}.{case}.compile.log").write_bytes(result.stdout)
    positive = case in POSITIVE
    expected_status = 0 if positive else 1
    assert result.returncode == expected_status, (
        f"{label}:{case} compile rc={result.returncode}: {result.stdout!r}"
    )
    footer(result.stdout, expected_status)
    if not positive:
        assert not binary.exists(), f"{label}:{case} emitted a binary after rejection"
        check_rejection(case, result.stdout)
        print(f"PASS[{label}:{case}] semantic member-result rejection", flush=True)
        return
    assert binary.is_file(), f"{label}:{case} did not emit a native executable"
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
    assert runtime.stdout == expected, (
        f"{label}:{case} stdout={runtime.stdout!r}, expected={expected!r}"
    )
    print(f"PASS[{label}:{case}] stdout={runtime.stdout!r}", flush=True)


def validate_packet():
    assert len(CASES) == len(set(CASES))
    assert {path.stem for path in FIXTURES.glob("*.cr")} == set(CASES)
    assert {path.stem for path in FIXTURES.glob("*.expected")} == set(POSITIVE)
    assert {path.stem for path in FIXTURES.glob("*.reject")} == set(NEGATIVE)
    for case in NEGATIVE:
        markers = [
            line.strip() for line in (FIXTURES / f"{case}.reject").read_bytes().splitlines()
            if line.strip()
        ]
        assert markers and len(markers) >= 3, (case, markers)
        assert all(markers), case
    print(f"PACKET_VALID structural-only {len(POSITIVE)} positive / {len(NEGATIVE)} negative cases")


def main():
    args = sys.argv[1:]
    if args == ["--self-test"]:
        validate_packet()
        return
    original_only = args == ["--original-only"]
    assert original_only or len(args) == 1, (
        "usage: run.py --self-test | --original-only | candidate-adamas"
    )
    root = find_root()
    safe = Path(os.environ.get("ADAMAS_RUN_SAFE", str(root / "scripts/run_safe.sh"))).resolve()
    original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or os.environ.get("ORIGINAL_CRYSTAL") or "crystal"
    original = Path(shutil.which(original_name) or original_name).resolve()
    candidate = None if original_only else Path(args[0]).resolve()
    assert safe.is_file() and os.access(safe, os.X_OK), safe
    assert original.is_file() and os.access(original, os.X_OK), original
    if candidate:
        assert candidate.is_file() and os.access(candidate, os.X_OK), candidate

    output = os.environ.get("CALLBACK_MEMBER_NATIVE_OUTPUT_DIR")
    if output:
        work = Path(output)
        assert work.is_absolute() and not work.exists(), work
        work.mkdir()
    else:
        work = Path(tempfile.mkdtemp(prefix="adamas_callback_member_native_"))
    try:
        stages = [("original", original)]
        for label, compiler in stages:
            failures = []
            for case in CASES:
                try:
                    run_case(label, compiler, case, work, safe)
                except Exception as exc:
                    failures.append((case, str(exc)))
                    print(f"FAIL[{label}:{case}] {exc}", flush=True)
            assert not failures, f"{label} failures: {failures}"
            print("ORIGINAL_PASS_COMPLETE[callback_member_native]", flush=True)

        if candidate is not None:
            for label in ("candidate-lazy", "candidate-eager"):
                failures = []
                for case in CASES:
                    try:
                        run_case(label, candidate, case, work, safe)
                    except Exception as exc:
                        failures.append((case, str(exc)))
                        print(f"FAIL[{label}:{case}] {exc}", flush=True)
                assert not failures, f"{label} failures: {failures}"
                print(f"{label.upper()}_PASS_COMPLETE[callback_member_native]", flush=True)
    finally:
        for binary in work.glob("*.program"):
            binary.unlink()
        for cache in work.glob("*.cache"):
            shutil.rmtree(cache)
        print("kept_logs=" + str(work), file=sys.stderr)


if __name__ == "__main__":
    main()
