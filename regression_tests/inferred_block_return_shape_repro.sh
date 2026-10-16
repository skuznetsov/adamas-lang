#!/usr/bin/env bash
# Keep inferred callback results local to their exact call specialization.
# The case subject consumes yield even in statement position; stdlib flat_map
# exercises deferred included-module lowering with alternating array results.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${COMPILER:-$ROOT_DIR/bin/adamas}}"
CASE="${2:-all}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$RUN_SAFE" && -x "$COMPILER" && -x "$ORIGINAL" ]] || {
  echo "usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0 /path/to/adamas [all|case|flat_map|included]" >&2
  exit 2
}
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inferred-block-result.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/case.cr" <<'CRYSTAL'
lib LibC
  fun putchar(c : Int32) : Int32
end

class CaseCallbackRelay
  def self.forward(& : -> _)
    case value = yield
    when Int32
      value
    else
      value
    end
  end
end

def emit_small(value : Int32)
  LibC.putchar(value)
end

def emit_wide(value : Int64)
  LibC.putchar(value.to_i32)
end

emit_small(CaseCallbackRelay.forward {65})
emit_wide(CaseCallbackRelay.forward {66_i64})
emit_small(CaseCallbackRelay.forward {67})
emit_wide(CaseCallbackRelay.forward {CaseCallbackRelay.forward {68_i64}})
CRYSTAL

cat >"$WORK_DIR/flat_map.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end

class FlatMapShapeRow
  def initialize(@value : Int32)
  end

  def diagnostics : Array(Int32)
    [@value]
  end

  def wide_diagnostics : Array(Int64)
    [@value.to_i64]
  end
end

def emit_ints(values : Array(Int32))
  values.each { |value| Probe.putchar(value) }
end

def emit_wide(values : Array(Int64))
  values.each { |value| Probe.putchar(value.to_i) }
end

rows = [FlatMapShapeRow.new(65), FlatMapShapeRow.new(66)]
emit_ints(rows.flat_map(&.diagnostics))
emit_wide(rows.flat_map(&.wide_diagnostics))
emit_ints(rows.flat_map(&.diagnostics))
emit_ints(rows.flat_map { |row| [row].flat_map(&.diagnostics) })
CRYSTAL

cat >"$WORK_DIR/included.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end

module RelayOps(T)
  def forward(value : T, & : T -> _)
    yield value
  end
end

module RelayLayer(T)
  include RelayOps(T)
end

class IncludedRelay(U)
  include RelayLayer(Int32)
end

class DirectRelay(U)
  include RelayLayer(Int32)
  def forward(value : Int32, & : Int32 -> _)
    yield value + 1
  end
end

def emit_small(value : Int32)
  Probe.putchar(value)
end

def emit_wide(value : Int64)
  Probe.putchar(value.to_i32)
end

relay = IncludedRelay(String).new
emit_small(relay.forward(65) { |value| value })
emit_wide(relay.forward(66) { |value| value.to_i64 })
emit_small(relay.forward(67) { |value| value })
emit_wide(relay.forward(68) { |value| relay.forward(value) { |inner| inner.to_i64 } })
direct = DirectRelay(String).new
emit_small(direct.forward(68) { |value| value })
CRYSTAL

build_and_run() {
  local name="$1" expected="$2" stage="$3" compiler="$4"
  local binary="$WORK_DIR/$name.$stage.bin"
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$compiler" build "$WORK_DIR/$name.cr" -o "$binary" --no-debug
             --link-flags="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
  else
    command=("$compiler" "$WORK_DIR/$name.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$binary")
    [[ "$name" != case ]] || command+=(--no-prelude)
  fi
  if ! env "CRYSTAL_CACHE_DIR=$WORK_DIR/$stage.cache" \
      "ADAMAS_EXTRA_LINK_FLAGS=${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      "$RUN_SAFE" "${command[0]}" 180 8192 "${command[@]:1}" \
      >"$WORK_DIR/$name.$stage.build.log" 2>&1; then
    tail -35 "$WORK_DIR/$name.$stage.build.log" >&2
    return 1
  fi
  rm -rf "$WORK_DIR/$stage.cache"
  if ! env RUN_SAFE_PASSTHROUGH_STDIO=1 \
      "$RUN_SAFE" "$binary" 15 1024 >"$WORK_DIR/$name.$stage.stdout" \
      2>"$WORK_DIR/$name.$stage.run.log"; then
    tail -35 "$WORK_DIR/$name.$stage.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$name.$stage.run.log"
  printf '%s' "$expected" >"$WORK_DIR/$name.expected"
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$name.$stage.stdout"
}

run_case() {
  local name="$1" expected="$2"
  build_and_run "$name" "$expected" original "$ORIGINAL"
  build_and_run "$name" "$expected" candidate "$COMPILER"
  diff -u "$WORK_DIR/$name.original.stdout" "$WORK_DIR/$name.candidate.stdout"
  printf 'PASS: %s inferred callback result\n' "$name"
}

case "$CASE" in
  all) run_case case ABCD; run_case flat_map ABABABAB; run_case included ABCDE ;;
  case) run_case case ABCD ;;
  flat_map) run_case flat_map ABABABAB ;;
  included) run_case included ABCDE ;;
  *) echo "unknown case: $CASE" >&2; exit 2 ;;
esac
