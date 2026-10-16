#!/usr/bin/env bash
# Module macros must preserve absolute class declarations and relative nesting.
# The stdlib thread_local getter and Random provide native consumer controls.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-macro-absolute-class.XXXXXX")"

cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 || "${KEEP_TMP:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL" ]]; then
  echo "ERROR: candidate and original compilers must be executable" >&2
  exit 2
fi

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end
class ModuleMacroRootTarget
  def self.base : Int32
    65
  end
end
module ModuleRootReopening
  macro reopen_root
    class ::ModuleMacroRootTarget
      def self.from_macro : Int32
        66
      end
    end
  end
  reopen_root
end
module ModuleRelativeDeclaration
  macro define_nested
    class ModuleMacroRootTarget
      def self.from_macro : Int32
        67
      end
    end
  end
  define_nested
end
class ModuleMacroCachedBox
  def initialize
    LibC.putchar(78)
  end
  def code : Int32
    65
  end
end
module ModuleMacroCachedOwner
  thread_local(box : ::ModuleMacroCachedBox) { ::ModuleMacroCachedBox.new }
end
LibC.putchar(ModuleMacroRootTarget.base)
LibC.putchar(ModuleMacroRootTarget.from_macro)
LibC.putchar(ModuleRelativeDeclaration::ModuleMacroRootTarget.from_macro)
LibC.putchar(ModuleMacroCachedOwner.box.code)
LibC.putchar(ModuleMacroCachedOwner.box.code)
Random.rand(2)
LibC.putchar([65].sample)
LibC.putchar(10)
CRYSTAL
printf 'ABCNAAA\n' >"$WORK_DIR/expected"

status=0
for stage in original candidate; do
  compiler="$COMPILER"
  args=("$WORK_DIR/probe.cr" --no-llvm-cache -o "$WORK_DIR/$stage")
  if [[ "$stage" == "original" ]]; then
    compiler="$ORIGINAL_CRYSTAL"
    args=(build "$WORK_DIR/probe.cr" -o "$WORK_DIR/$stage" --error-trace --link-flags=-fuse-ld=/usr/bin/ld)
  fi
  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.build.resources" \
      "$ROOT_DIR/scripts/run_safe.sh" "$compiler" 180 8192 "${args[@]}" \
      >"$WORK_DIR/$stage.build.log" 2>&1; then
    echo "FAIL[$stage]: compilation failed" >&2
    tail -20 "$WORK_DIR/$stage.build.log" >&2
    status=1
    continue
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.run.resources" \
      "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$stage" 10 512 \
      >"$WORK_DIR/$stage.actual" 2>"$WORK_DIR/$stage.run.log"; then
    echo "FAIL[$stage]: runtime failed" >&2
    tail -20 "$WORK_DIR/$stage.run.log" >&2
    status=1
    continue
  fi
  if diff -u "$WORK_DIR/expected" "$WORK_DIR/$stage.actual" >&2; then
    echo "PASS[$stage]: absolute module classes, relative shadowing, cached construction and Array#sample"
  else
    echo "FAIL[$stage]: module macro class binding output differs" >&2
    status=1
  fi
done
exit "$status"
