#!/usr/bin/env python3
"""Original-first runtime checks for Atomic source-authority isolation."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
CASES = json.loads((HERE / "cases.json").read_text())
EXIT_LINE = re.compile(rb"\[EXIT: 0\] after ~[0-9]+s\n")
RESOURCE_LINE = re.compile(
    rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit "
    rb"exit_code=0(?: [A-Za-z0-9_]+=[A-Za-z0-9_.,:-]+)+\n"
)


def root_for(candidate):
    configured = os.environ.get("ADAMAS_ROOT")
    if configured:
        root = Path(configured).resolve()
        if (root / "scripts/run_safe.sh").is_file():
            return root
        raise RuntimeError(f"ADAMAS_ROOT has no scripts/run_safe.sh: {root}")
    anchors = [Path.cwd().resolve()]
    if candidate:
        anchors.append(candidate.parent)
    for anchor in anchors:
        for parent in (anchor, *anchor.parents):
            if (parent / "scripts/run_safe.sh").is_file():
                return parent
    raise RuntimeError("set ADAMAS_ROOT or run from an Adamas checkout")


def executable(value, label):
    path = Path(value).expanduser().resolve()
    if not path.is_file() or not os.access(path, os.X_OK):
        raise RuntimeError(f"{label} is not an executable file: {path}")
    return path


def safe_environment(cache, tmp, *, eager=None, passthrough=False):
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("ADAMAS_", "DEBUG_", "RUN_SAFE_"))}
    if flags := os.environ.get("ADAMAS_EXTRA_LINK_FLAGS"):
        env["ADAMAS_EXTRA_LINK_FLAGS"] = flags
    env["CRYSTAL_CACHE_DIR"] = str(cache)
    env["ADAMAS_LLVM_CACHE"] = "0"
    env["TMPDIR"] = str(tmp)
    env["RUN_SAFE_PASSTHROUGH_STDIO"] = "1" if passthrough else "0"
    env.pop("RUN_SAFE_RESOURCE_FILE", None)
    env.pop("ADAMAS_EAGER_MONO", None)
    if eager:
        env["ADAMAS_EAGER_MONO"] = "1"
    return env


def safe_footer(stderr):
    lines = stderr.splitlines(keepends=True)
    if len(lines) != 2 or not EXIT_LINE.fullmatch(lines[-2]) or not RESOURCE_LINE.fullmatch(lines[-1]):
        raise AssertionError(f"missing successful run_safe footer: {stderr!r}")


def compile_case(label, compiler, source, binary, cache, tmp, safe, *, eager=None, emit_ir=False):
    cache.mkdir()
    tmp.mkdir()
    env = safe_environment(cache, tmp, eager=eager)
    if label == "original":
        args = ["build", "--no-debug", "--prelude=empty", str(source), "-o", str(binary)]
        if sys.platform == "darwin":
            args.insert(3, "--link-flags=-fuse-ld=/usr/bin/ld")
    else:
        args = [
            str(source), "--no-prelude", "--no-debug", "--no-ast-cache",
            "--no-llvm-cache", "-o", str(binary),
        ]
    if emit_ir:
        # Keep the IR command explicit for both compiler front ends.
        if label == "original":
            args = ["build", "--no-debug", "--prelude=empty"]
            if sys.platform == "darwin":
                args.append("--link-flags=-fuse-ld=/usr/bin/ld")
        else:
            args = ["--no-prelude", "--no-debug", "--no-ast-cache", "--no-llvm-cache"]
        args.extend(["--emit", "llvm-ir", str(source), "-o", str(binary)])
    result = subprocess.run(
        [str(safe), str(compiler), "120", "4096", *args],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=140,
    )
    expected_file = binary.with_suffix(".ll") if emit_ir else binary
    if result.returncode != 0 or not expected_file.is_file():
        raise AssertionError(
            f"{label} compile failed rc={result.returncode}: {result.stdout[-5000:]!r}"
        )


def run_case(label, compiler, case, work, safe, *, eager=None):
    source = HERE / case["source"]
    stem = f"{label}_{case['name']}_{'eager' if eager else 'lazy'}"
    binary = work / f"{stem}.bin"
    cache = work / f"{stem}.cache"
    tmp = work / f"{stem}.tmp"
    try:
        compile_case(label, compiler, source, binary, cache, tmp, safe, eager=eager)
        env = safe_environment(cache, tmp, eager=eager, passthrough=True)
        result = subprocess.run(
            [str(safe), str(binary), "5", "512"],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
        )
        if result.returncode != 0:
            raise AssertionError(f"runtime exit={result.returncode}; stderr={result.stderr!r}")
        safe_footer(result.stderr)
        expected = case["expected"].encode()
        if result.stdout != expected:
            raise AssertionError(f"stdout={result.stdout!r}, expected={expected!r}")
        mode = "original" if label == "original" else ("candidate eager" if eager else "candidate lazy")
        print(f"PASS {mode} {case['name']} stdout={result.stdout!r}", flush=True)
    finally:
        if binary.exists():
            binary.unlink()
        shutil.rmtree(cache, ignore_errors=True)
        shutil.rmtree(tmp, ignore_errors=True)



def check_genuine_fence(label, compiler, work, safe, *, eager=None):
    source = HERE / "genuine_annotated_fence.cr"
    stem = f"{label}_genuine_fence_{'eager' if eager else 'lazy'}"
    binary = work / stem
    cache = work / f"{stem}.cache"
    tmp = work / f"{stem}.tmp"
    ir = binary.with_suffix(".ll")
    try:
        compile_case(label, compiler, source, binary, cache, tmp, safe,
                     eager=eager, emit_ir=True)
        if not ir.is_file() or not re.search(r"^\s*fence\s+seq_cst\s*$", ir.read_text(), re.M):
            raise AssertionError(f"{label} did not emit a sequentially consistent fence: {ir}")
        mode = "original" if label == "original" else ("candidate eager" if eager else "candidate lazy")
        print(f"PASS {mode} genuine_annotated_fence opcode=fence seq_cst", flush=True)
    finally:
        if binary.exists():
            binary.unlink()
        if ir.exists():
            ir.unlink()
        shutil.rmtree(cache, ignore_errors=True)
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    args = sys.argv[1:]
    original_only = args == ["--original-only"]
    if not original_only and len(args) != 1:
        raise SystemExit("usage: atomic_primitive_source_authority_repro.sh --original-only | CANDIDATE_ADAMAS")
    candidate = None if original_only else Path(args[0]).expanduser().resolve()
    root = root_for(candidate)
    safe = executable(os.environ.get("ADAMAS_RUN_SAFE", str(root / "scripts/run_safe.sh")), "run_safe.sh")
    crystal_name = (os.environ.get("ORIGINAL_CRYSTAL_BIN") or
                    os.environ.get("ORIGINAL_CRYSTAL") or
                    os.environ.get("CRYSTAL_BIN") or "crystal")
    crystal_path = shutil.which(crystal_name) or crystal_name
    original = executable(crystal_path, "original Crystal compiler")
    candidate = executable(candidate, "candidate Adamas compiler") if candidate else None

    work = Path(tempfile.mkdtemp(prefix="adamas_atomic_source_authority_"))
    try:
        # Complete every stock case before attempting either candidate mode.
        for case in CASES:
            run_case("original", original, case, work, safe)
        check_genuine_fence("original", original, work, safe)
        print("ORIGINAL_PASS_COMPLETE[atomic_source_authority]", flush=True)
        if candidate:
            for eager in (False, True):
                for case in CASES:
                    run_case("candidate", candidate, case, work, safe, eager=eager)
                check_genuine_fence("candidate", candidate, work, safe, eager=eager)
                mode = "eager" if eager else "lazy"
                print(f"CANDIDATE_PASS_COMPLETE[atomic_source_authority:{mode}]", flush=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
