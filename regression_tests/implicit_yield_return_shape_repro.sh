#!/usr/bin/env bash
# Implicit yield callbacks need separate wrappers for different result ABIs,
# including when String.build forces the nested callback out of the inline path.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
CANDIDATE="${1:-$ROOT/bin/adamas}"
[[ -x "$SAFE" && -x "$ORIGINAL" && -x "$CANDIDATE" ]] || {
  echo "usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0 /path/to/adamas" >&2
  exit 2
}
WORK="$(mktemp -d "${TMPDIR:-/tmp}/implicit-yield-return-shape.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK/original.cache" "$WORK/candidate.cache"
  if [[ "$status" == 0 && "${KEEP_ARTIFACTS:-0}" != 1 ]]; then
    rm -rf "$WORK"
  else
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  fi
}
trap cleanup EXIT

cat >"$WORK/common.cr" <<'CRYSTAL'
lib YieldShapeProbe
  fun putchar(value : Int32) : Int32
end

def yield_shape_identity(value)
  value
end

def yield_shape_forward
  yield
end

def yield_shape_emit_int(value : Int32) : Nil
  YieldShapeProbe.putchar(value)
  nil
end

def yield_shape_emit_float(value : Float64) : Nil
  # Observe the payload, not just whether the callback returned.
  if value == 1.25
    YieldShapeProbe.putchar(70)
  else
    YieldShapeProbe.putchar(88)
  end
  nil
end
CRYSTAL

cases=(int_only float_then_int int_then_float warm_float_then_int)
for name in "${cases[@]}"; do
  cp "$WORK/common.cr" "$WORK/$name.cr"
  if [[ "$name" == warm_float_then_int ]]; then
    echo 'yield_shape_emit_float(yield_shape_forward { 1.25 })' >>"$WORK/$name.cr"
  fi
  echo 'String.build do |io|' >>"$WORK/$name.cr"
  if [[ "$name" == float_then_int ]]; then
    echo '  yield_shape_emit_float(yield_shape_forward { 1.25 })' >>"$WORK/$name.cr"
  fi
  echo '  yield_shape_emit_int(yield_shape_forward { yield_shape_identity(67) })' >>"$WORK/$name.cr"
  if [[ "$name" == int_then_float ]]; then
    echo '  yield_shape_emit_float(yield_shape_forward { 1.25 })' >>"$WORK/$name.cr"
  fi
  cat >>"$WORK/$name.cr" <<'CRYSTAL'
  io << "x"
end
YieldShapeProbe.putchar(10)
CRYSTAL
  case "$name" in
    int_only) printf 'C\n' >"$WORK/$name.expected" ;;
    int_then_float) printf 'CF\n' >"$WORK/$name.expected" ;;
    *) printf 'FC\n' >"$WORK/$name.expected" ;;
  esac
done

build_and_run() {
  local stage="$1" name="$2"
  local binary="$WORK/$stage.$name.bin"
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$ORIGINAL" build "$WORK/$name.cr" --single-module --no-debug)
    if [[ "$(uname -s)" == Darwin ]]; then
      command+=(--link-flags="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
    fi
  else
    # Full prelude is intentional: removing it hides the wrapper collision.
    command=("$CANDIDATE" "$WORK/$name.cr" --no-debug --no-ast-cache --no-llvm-cache)
  fi
  if ! env CRYSTAL_CACHE_DIR="$WORK/$stage.cache" \
      "$SAFE" "${command[0]}" 120 8192 "${command[@]:1}" -o "$binary" \
      >"$WORK/$stage.$name.compile.log" 2>&1; then
    tail -40 "$WORK/$stage.$name.compile.log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 10 512 \
      >"$WORK/$stage.$name.stdout" 2>"$WORK/$stage.$name.run.log"; then
    tail -40 "$WORK/$stage.$name.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK/$stage.$name.run.log"
  cmp "$WORK/$name.expected" "$WORK/$stage.$name.stdout"
}

# Qualify every byte string on pristine Crystal before invoking the candidate.
for name in "${cases[@]}"; do build_and_run original "$name"; done
for name in "${cases[@]}"; do build_and_run candidate "$name"; done
echo 'PASS: implicit yield callback result ABI survives sibling order and String.build'
