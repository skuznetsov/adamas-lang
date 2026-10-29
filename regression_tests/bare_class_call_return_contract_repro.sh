#!/usr/bin/env bash
# Class helper results must come from the selected source declaration, including
# named actuals and defaults. The HIR spec separately forces absent return caches.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bare-class-call-return.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL" ]] || exit 2

cat >"$WORK/selected_results.cr" <<'CRYSTAL'
lib LibC
  fun putchar(c : Int32) : Int32
end

class ClassReturnProbe
  def self.pick(value : Int32) : Int32
    value
  end
  def self.pick(value : String) : String
    value
  end
  def self.inferred(value : Int32)
    value
  end
  def self.inferred(value : String)
    value
  end
  def self.default_value(first = "default", second = first)
    second
  end
  def self.named_only(*, first, second)
    second
  end
  def self.external(label value)
    value
  end
  def self.external_default(label value = "fallback")
    value
  end
  def self.collide
    1
  end
  def collide
    "instance"
  end
  def self.observe(value : Int32)
    LibC.putchar(73)
  end
  def self.observe(value : String)
    LibC.putchar(83)
  end
  def self.run
    observe(pick(value: 1))
    observe(pick(value: "named"))
    observe(inferred(2))
    observe(inferred(value: "body"))
    observe(default_value())
    observe(named_only(second: "named-only", first: 3))
    observe(collide())
    observe(external(label: 4))
    observe(external_default(label: 5))
    observe(external_default())
    LibC.putchar(10)
  end
end
ClassReturnProbe.run
CRYSTAL
printf 'ISISSSIIIS\n' >"$WORK/expected"

cat >"$WORK/reject_named_value.cr" <<'CRYSTAL'
class ClassReturnNegative
  def self.pick(value : Int32) : Int32
    value
  end
  def self.pick(value : String) : String
    value
  end
  def self.run
    pick(value: 1.0_f64)
  end
end
ClassReturnNegative.run
CRYSTAL

ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)

compile_case() {
  local stage="$1" name="$2" status=0
  local -a command_args
  if [[ "$stage" == original ]]; then
    command_args=("$ORIGINAL" 120 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    command_args=("$COMPILER" 120 8192 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  CRYSTAL_CACHE_DIR="$WORK/cache.$stage.$name" ADAMAS_LLVM_CACHE=0 \
    "$SAFE_RUNNER" "${command_args[@]}" "$WORK/$name.cr" -o "$WORK/$stage.$name.bin" \
    >"$WORK/$stage.$name.compile.log" 2>&1 || status=$?
  return "$status"
}

# Qualify all outcomes with the original before evaluating the candidate.
for stage in original adamas; do
  if ! compile_case "$stage" selected_results; then
    cat "$WORK/$stage.selected_results.compile.log" >&2
    exit 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK/$stage.selected_results.bin" 5 512 \
    >"$WORK/$stage.stdout" 2>"$WORK/$stage.run.log" || {
      cat "$WORK/$stage.run.log" >&2
      exit 1
    }
  diff -u "$WORK/expected" "$WORK/$stage.stdout"
  status=0
  compile_case "$stage" reject_named_value || status=$?
  if [[ "$status" != 1 || -e "$WORK/$stage.reject_named_value.bin" ]]; then
    cat "$WORK/$stage.reject_named_value.compile.log" >&2
    echo "FAIL[$stage]: expected semantic rejection" >&2
    exit 1
  fi
  python3 - "$WORK/$stage.reject_named_value.compile.log" <<'PY_REJECT'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(errors="replace").lower()
assert "pick" in text and "float64" in text, text
assert "syntax error" not in text and "parser errors" not in text, text
assert "error" in text, text
PY_REJECT
  echo "PASS[$stage]: selected class results and strict named-value rejection"
done
