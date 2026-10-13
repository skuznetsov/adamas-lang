#!/usr/bin/env bash
# Preserve both union variants, the object accumulator, and the object return
# across an untyped raw callback. This models the Path/Tuple reduce boundary.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-crystal}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/raw_yield_object_union.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$WORKDIR"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT
[[ -x "$COMPILER" ]] || { echo "error: compiler not executable: $COMPILER" >&2; exit 2; }
cat >"$WORKDIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class CallbackPath
  def initialize(@value : Int32)
  end

  def value : Int32
    @value
  end

  def join(part : CallbackPath) : CallbackPath
    CallbackPath.new(@value + part.@value)
  end

  def join(part : String) : CallbackPath
    CallbackPath.new(@value + 1)
  end
end

class CallbackTuple
  @first : CallbackPath | String
  @second : CallbackPath | String

  def initialize(@first : CallbackPath | String, @second : CallbackPath | String)
  end

  def reduce(memo, &block)
    memo = yield memo, @first
    memo = yield memo, @second
    memo
  end
end

def reduce_paths(parts : CallbackTuple, &block)
  parts.reduce(CallbackPath.new(10)) { |path, part| path.join(part) }
end

parts = CallbackTuple.new(CallbackPath.new(2), "x")
result = reduce_paths(parts) { |path, part| path.join(part) }
LibC.exit(81) unless result.value == 13
reverse = CallbackTuple.new("x", CallbackPath.new(2))
reverse_result = reduce_paths(reverse) { |path, part| path.join(part) }
LibC.exit(82) unless reverse_result.value == 13
LibC.exit(0)
CR
for mode in original adamas; do
  if [[ "$mode" == original ]]; then
    build=("$ORIGINAL_CRYSTAL" 120 8192 build "$WORKDIR/repro.cr")
  else
    build=("$COMPILER" 120 8192 "$WORKDIR/repro.cr" --no-prelude)
  fi
  if ! ADAMAS_DISABLE_INLINE_YIELD=1 CRYSTAL_CACHE_DIR="$WORKDIR/$mode-cache" \
    "$RUN_SAFE" "${build[@]}" -o "$WORKDIR/$mode.bin" >"$WORKDIR/$mode.compile.log" 2>&1; then
    echo "FAIL: $mode object-union callback compilation" >&2
    tail -40 "$WORKDIR/$mode.compile.log" >&2
    exit 1
  fi
  if ! "$RUN_SAFE" "$WORKDIR/$mode.bin" 5 512 >"$WORKDIR/$mode.run.log" 2>&1; then
    echo "FAIL: $mode object-union callback runtime" >&2
    cat "$WORKDIR/$mode.run.log" >&2
    exit 1
  fi
done
echo "PASS: untyped callback preserves object accumulator, union variants, and object return"
