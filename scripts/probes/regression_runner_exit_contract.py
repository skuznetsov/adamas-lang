#!/usr/bin/env python3
"""Manual RED probe: actual regression runners must reject nonzero test exits.

Run from the repository root:
  scripts/run_safe.sh /usr/bin/python3 45 512 scripts/probes/regression_runner_exit_contract.py

Uses fake compilers in disposable trees; does not build or edit the compiler.
Exit 1 means the runtime verdict contract is violated, not a probe success.
Promote these cases into runner specs when repairing the runners.
"""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SAFE = ROOT / "scripts/run_safe.sh"
FAKE_COMPILER = """#!/bin/bash
src="${!#}"
name=$(basename "$src" .cr)
case "$name" in
  compile_fail) exit 3 ;;
  no_binary) exit 0 ;;
esac
rc=0
case "$name" in *_exit7) rc=7 ;; esac
printf '#!/bin/bash\nprintf "MARKER\\n"\nexit %s\n' "$rc" > "${src%.cr}"
chmod +x "${src%.cr}"
"""


def check_runner(runner, combined):
    cases = {
        "marker_ok": True,
        "marker_exit7": False,
        "unmarked_ok": True,
        "unmarked_exit7": False,
        "wrong_marker": False,
        "compile_fail": False,
        "no_binary": False,
    }
    if combined:
        cases.update(golden_ok=True, golden_exit7=False, golden_wrong=False)
    with tempfile.TemporaryDirectory(prefix="adamas-runner-contract-") as name:
        work = Path(name)
        fixture_dir = work / "regression_tests"
        if combined:
            fixture_dir /= "combined"
        fixture_dir.mkdir(parents=True)
        (work / "scripts").mkdir()
        (work / "scripts/run_safe.sh").symlink_to(SAFE)
        copied_runner = work / "runner.sh"
        shutil.copyfile(ROOT / "regression_tests" / runner, copied_runner)
        compiler = work / "fake_compiler.sh"
        compiler.write_text(FAKE_COMPILER)
        compiler.chmod(0o755)
        for case in cases:
            marker = "MARKER" if case.startswith("marker_") else None
            if case == "wrong_marker":
                marker = "EXPECTED_OTHER"
            (fixture_dir / f"{case}.cr").write_text(
                f"# EXPECT: {marker}\n" if marker else "# Fake compiler fixture\n"
            )
            if case.startswith("golden_"):
                (fixture_dir / f"{case}.out").write_text(
                    "WRONG\n" if case == "golden_wrong" else "MARKER\n"
                )
        result = subprocess.run(
            [str(SAFE), "/bin/bash", "20", "512", str(copied_runner), str(compiler), "1"],
            cwd=work, text=True, capture_output=True, check=False,
        )
        observed = {}
        for line in result.stdout.splitlines():
            match = re.match(r"^\s*(PASS|FAIL(?: \([^)]*\))?): (\w+)(?:\s|$)", line)
            if match:
                observed[match[2]] = match[1] == "PASS"
        violations = 0
        for case, expected in cases.items():
            actual = observed.get(case)
            ok = actual is expected
            violations += not ok
            print(f"{runner} {case}: expected_pass={expected} actual_pass={actual} contract={'OK' if ok else 'VIOLATED'}")
        if result.returncode != 1:
            # Every fixture set contains intentional output/compile failures.
            violations += 1
            print(f"{runner}: expected aggregate exit 1, got {result.returncode}")
        if set(observed) != set(cases):
            print(result.stdout)
            print(result.stderr)
        return violations


if __name__ == "__main__":
    violations = check_runner("run_all.sh", False) + check_runner("run_combined.sh", True)
    print(f"Runtime verdict contract violations: {violations}")
    raise SystemExit(1 if violations else 0)
