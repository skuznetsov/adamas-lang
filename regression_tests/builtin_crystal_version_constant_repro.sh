#!/usr/bin/env bash
# Regression: program-defined `Crystal::VERSION` / `Crystal::LLVM_VERSION`.
# Original Crystal defines these in Program#define_crystal_constants; they have
# no source declaration. V2 lowered a runtime read of them to the Int32 zero
# path fallback, so any String use dereferenced null (segfault).
# Bootstrap impact: the macro evaluator reads `::Crystal::VERSION` at runtime,
# so a self-built compiler evaluated `compare_versions(Crystal::VERSION, ...)`
# against nil and dropped both branches of stdlib version guards
# (e.g. String CHAR_TO_DIGIT), which crashed `"922".to_i64?` in stage 3.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/builtin_crystal_version_constant_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/cv.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
  fun strlen(p : UInt8*) : UInt64
end

class Foo
  def rt_version : String
    ::Crystal::VERSION
  end

  def rt_version_unanchored : String
    Crystal::VERSION
  end

  def rt_llvm : String
    ::Crystal::LLVM_VERSION
  end

  def mt_version : String
    {{ ::Crystal::VERSION }}
  end

  def mt_llvm : String
    {{ ::Crystal::LLVM_VERSION }}
  end
end

f = Foo.new
code = 0
v = LibC.strlen(f.rt_version.to_unsafe)
code |= 1 unless v > 0 && v == LibC.strlen(f.mt_version.to_unsafe)
code |= 2 unless LibC.strlen(f.rt_version_unanchored.to_unsafe) == v
l = LibC.strlen(f.rt_llvm.to_unsafe)
code |= 4 unless l > 0 && l == LibC.strlen(f.mt_llvm.to_unsafe)
code |= 8 unless f.rt_version.to_unsafe.value == f.mt_version.to_unsafe.value
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/cv.cr" --no-prelude -o "$WORK_DIR/cv" >"$WORK_DIR/cv.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/cv.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/cv" 5 512 >"$WORK_DIR/cv.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/cv.run.log"; then
  echo "FAIL: runtime Crystal::VERSION / LLVM_VERSION not defined as program constants" >&2
  cat "$WORK_DIR/cv.run.log" >&2
  exit 1
fi
echo "PASS: program-defined Crystal version constants lower to their string values"
