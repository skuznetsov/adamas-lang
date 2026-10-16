#!/usr/bin/env bash
# Forwarded typed Procs must use their bound input/result ABI, as proc.call does.
# The stdlib sorting path forwards a UInt64/tuple comparator returning Int32;
# resolving the generic Proc#call method first incorrectly publishes its R.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${COMPILER:-$ROOT_DIR/bin/adamas}}"
CASE="${2:-all}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$RUN_SAFE" && -x "$COMPILER" && -x "$ORIGINAL" ]] || {
  echo "usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0 /path/to/adamas [all|sort|types]" >&2
  exit 2
}
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/forwarded-proc-abi.XXXXXX")"
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

cat >"$WORK_DIR/sort.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end

values = [3_u64, 1_u64, 2_u64]
values.sort! { |left, right| left <=> right }
values.each { |value| Probe.putchar(value.to_i32 + 48) }
values = [3_u64, 1_u64, 2_u64]
values.sort_by! { |value| value }
values.each { |value| Probe.putchar(value.to_i32 + 48) }
values.sort! { |left, right| right <=> left }
values.each { |value| Probe.putchar(value.to_i32 + 48) }
floats = [3.0, 1.0, 2.0]
floats.sort_by! { |value| value }
floats.each { |value| Probe.putchar(value.to_i32 + 48) }
CRYSTAL

cat >"$WORK_DIR/types.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end

def accept_i64(&block : Int32 -> Int64)
  yield 1
end

def relay_i64(&block : Int32 -> Int64)
  accept_i64(&block)
end

def accept_float(&block : Int32 -> Float64)
  yield 1
end

def relay_float(&block : Int32 -> Float64)
  accept_float(&block)
end

def accept_nil(&block : Int32 ->)
  yield 1
end

def relay_nil(&block : Int32 ->)
  accept_nil(&block)
end

Probe.putchar(relay_i64 { |value| value.to_i64 + 64_i64 }.to_i32)
Probe.putchar(relay_float { |value| value.to_f64 + 65.0 }.to_i32)
relay_nil { |value| Probe.putchar(value + 66); nil }
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
    [[ "$name" != types ]] || command+=(--no-prelude)
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
  printf 'PASS: %s forwarded Proc ABI\n' "$name"
}

case "$CASE" in
  all) run_case sort 123123321123; run_case types ABC ;;
  sort) run_case sort 123123321123 ;;
  types) run_case types ABC ;;
  *) echo "unknown case: $CASE" >&2; exit 2 ;;
esac
