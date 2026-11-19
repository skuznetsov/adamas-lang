#!/usr/bin/env python3
"""Stock-first oracle for deferred property-setter source results."""
from pathlib import Path
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
POSITIVE = (
    "reader", "chain", "setter_body_result", "initializer_result", "class_result",
    "class_input", "terminal_rhs", "setter_instance_then_class", "setter_class_then_instance",
    "setter_param_instance_then_class", "setter_param_class_then_instance",
    "numeric_setter_argument", "virtual_class_setter_result",
)
NEGATIVE = (
    "reject_class_result_as_instance", "reject_invalid_return",
    "reject_instance_for_class_input", "reject_class_for_instance_input",
    "reject_setter_grouped_literal", "reject_setter_explicit_grouped_literal",
    "reject_setter_numeric_local_narrowing", "reject_setter_numeric_overflow",
    "reject_setter_unsigned_negative", "reject_setter_ambiguous_numeric",
    "reject_virtual_class_setter_rhs_as_result",
)
CASES = POSITIVE + NEGATIVE
EXIT = re.compile(rb"\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n")
RESOURCE = re.compile(
    rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit "
    rb"exit_code=([0-9]+)(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n"
)
BAD_REJECTION = (
    b"parse error", b"syntax error", b"segmentation fault", b"stack overflow",
    b"failed to emit", b"could not emit", b"llvm error", b"bus error",
    b"unhandled exception", b"compiler bug", b"timed out", b"resource limit",
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
    raise RuntimeError("set ADAMAS_ROOT to the Adamas source snapshot")


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


def compiler_command(label, compiler, source, binary):
    if label == "original":
        args = ["build", "--prelude=empty", "--no-debug", str(source), "-o", str(binary)]
        if platform.system() == "Darwin":
            args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        return args
    return [
        str(source), "--no-prelude", "--no-debug", "--no-ast-cache",
        "--no-llvm-cache", "-o", str(binary),
    ]


def run_case(label, compiler, case, work, safe):
    source = HERE / f"{case}.cr"
    binary = work / f"{label}.{case}.program"
    cache = work / f"{label}.{case}.cache"
    cache.mkdir()
    env = {**os.environ, "CRYSTAL_CACHE_DIR": str(cache), "ADAMAS_LLVM_CACHE": "0"}
    if label == "candidate-lazy":
        env.pop("ADAMAS_EAGER_HIR", None)
        env.pop("ADAMAS_EAGER_MONO", None)
    elif label == "candidate-eager":
        env.pop("ADAMAS_EAGER_HIR", None)
        env["ADAMAS_EAGER_MONO"] = "1"
    if label.startswith("candidate") and platform.system() == "Darwin":
        env["ADAMAS_EXTRA_LINK_FLAGS"] = os.environ.get(
            "ADAMAS_EXTRA_LINK_FLAGS", "-fuse-ld=/usr/bin/ld"
        )
    command = [
        str(safe), str(compiler), "120", "4096",
        *compiler_command("original" if label == "original" else "candidate", compiler, source, binary),
    ]
    result = subprocess.run(
        command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145
    )
    (work / f"{label}.{case}.compile.log").write_bytes(result.stdout)
    positive = case in POSITIVE
    expected_status = 0 if positive else 1
    assert result.returncode == expected_status, (
        f"{label}:{case} compile rc={result.returncode}: {result.stdout!r}"
    )
    footer(result.stdout, expected_status)
    if not positive:
        lowered = result.stdout.lower()
        markers = [
            line.strip().lower()
            for line in (HERE / f"{case}.reject").read_bytes().splitlines()
            if line.strip()
        ]
        assert markers and all(marker in lowered for marker in markers), (
            f"{label}:{case} missing semantic markers {markers!r}: {result.stdout!r}"
        )
        assert b"error:" in lowered and not any(x in lowered for x in BAD_REJECTION), result.stdout
        if case in ("reject_instance_for_class_input", "reject_class_for_instance_input"):
            assert b"no overload matches" in lowered or b"expected argument" in lowered, result.stdout
        assert not binary.exists(), f"{label}:{case} emitted a binary after rejection"
        print(f"PASS[{label}:{case}] semantic rejection", flush=True)
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
    expected = (HERE / f"{case}.expected").read_bytes()
    assert runtime.stdout == expected, (
        f"{label}:{case} stdout={runtime.stdout!r}, expected={expected!r}"
    )
    print(f"PASS[{label}:{case}] stdout={runtime.stdout!r}", flush=True)


def validate_packet():
    assert {path.stem for path in HERE.glob("*.cr")} == set(CASES)
    assert {path.stem for path in HERE.glob("*.expected")} == set(POSITIVE)
    assert {path.stem for path in HERE.glob("*.reject")} == set(NEGATIVE)
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
    validate_packet()
    root = find_root()
    safe = Path(os.environ.get("ADAMAS_RUN_SAFE", str(root / "scripts/run_safe.sh"))).resolve()
    original_name = os.environ.get("ORIGINAL_CRYSTAL_BIN") or "crystal"
    original = Path(shutil.which(original_name) or original_name).resolve()
    candidate = None if original_only else Path(args[0]).resolve()
    assert safe.is_file() and os.access(safe, os.X_OK), safe
    assert original.is_file() and os.access(original, os.X_OK), original
    if candidate:
        assert candidate.is_file() and os.access(candidate, os.X_OK), candidate

    work = Path(tempfile.mkdtemp(prefix="adamas_deferred_setter_native_"))
    try:
        for label, compiler in [("original", original)]:
            for case in CASES:
                run_case(label, compiler, case, work, safe)
            print("ORIGINAL_PASS_COMPLETE[deferred_setter_source_result]", flush=True)
        if candidate:
            for label in ("candidate-lazy", "candidate-eager"):
                for case in CASES:
                    run_case(label, candidate, case, work, safe)
                print(f"{label.upper()}_PASS_COMPLETE[deferred_setter_source_result]", flush=True)
    finally:
        for binary in work.glob("*.program"):
            binary.unlink()
        for cache in work.glob("*.cache"):
            shutil.rmtree(cache)
        print("kept_logs=" + str(work), file=sys.stderr)


if __name__ == "__main__":
    main()
