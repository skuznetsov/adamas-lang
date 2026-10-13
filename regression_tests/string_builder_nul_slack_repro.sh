#!/usr/bin/env bash
# String::Builder#to_s writes its NUL terminator at @buffer[real_bytesize], but
# increase_capacity_by only guarantees real_bytesize <= @capacity, so the
# terminator can land one byte past the allocation. Keep the stdlib unchanged:
# codegen restores slack through @__adamas_gc_atomic_malloc for both managed
# and native allocation. The GC.realloc native fallback is also padded by one.
# The IR guard checks the reserved byte even when an allocator would tolerate
# an overflow during the runtime probe.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/string-builder-nul-slack.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

# String.build(51): capacity = 51 + String::HEADER_SIZE (12) + 1 = 64.
# A 52-byte body makes real_bytesize = 52 + 12 = 64 == capacity, so #to_s
# stores the terminator at @buffer[64] on a 64-byte request. Repeat the boundary
# case; the IR guard establishes the spare byte independently of heap behavior.
cat >"$WORK_DIR/nul_slack.cr" <<'CR'
body = "a" * 52
i = 0
n = 0
while i < 200000
  s = String.build(51) { |io| io << body }
  n += s.bytesize
  i += 1
end
STDERR.puts "nul_slack n=#{n}"
STDERR.flush
CR

BIN="$WORK_DIR/nul_slack"
COMPILE_LOG="$WORK_DIR/compile.log"
RUN_LOG="$WORK_DIR/run.log"

# Normal builds keep the IR beside the linked runtime probe.
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/nul_slack.cr" --no-llvm-cache -o "$BIN" >"$COMPILE_LOG" 2>&1; then
  echo "compile failed" >&2
  tail -60 "$COMPILE_LOG" >&2
  exit 1
fi

LL="$BIN.ll"
if [[ ! -s "$LL" ]]; then
  echo "regression: compilation produced no $LL" >&2
  exit 1
fi
if [[ ! -x "$BIN" ]]; then
  echo "regression: compilation produced no executable $BIN" >&2
  exit 1
fi

# Body of one LLVM function definition, by exact define line prefix.
fn_body() {
  awk -v want="$1" '
    index($0, want) == 1 { inside = 1 }
    inside { print }
    inside && $0 == "}" { exit }
  ' "$LL"
}

# The slack allocator must exist and actually add the spare byte.
slack_body="$(fn_body 'define ptr @__adamas_gc_atomic_malloc(i64 %size)')"
if [[ -z "$slack_body" ]]; then
  echo "regression: @__adamas_gc_atomic_malloc is not defined" >&2
  exit 1
fi
rg -q '%slack = add i64 %size, 1' <<<"$slack_body" || {
  echo "regression: @__adamas_gc_atomic_malloc does not reserve terminator slack" >&2
  exit 1
}
rg -q 'call ptr (@GC_malloc_atomic\(i64 %slack\)|%fn\(i64 1, i64 %slack\))' <<<"$slack_body" || {
  echo "regression: atomic allocation does not use the padded size" >&2
  exit 1
}

# The stdlib GC.malloc_atomic funnel must route through it. Before the fix this
# body called @__adamas_malloc64 directly, i.e. an exact-size libc allocation
# with no room for String::Builder#to_s's terminator.
funnel_body="$(fn_body 'define ptr @GC$Dmalloc_atomic$$UInt64(i64 %size)')"
if [[ -z "$funnel_body" ]]; then
  echo "regression: GC.malloc_atomic funnel was not emitted" >&2
  exit 1
fi
allocation_result="$(sed -nE 's/^  (%[^ ]+) = call ptr @__adamas_gc_atomic_malloc\(i64 %size\)$/\1/p' <<<"$funnel_body")"
if [[ -z "$allocation_result" ]] || ! grep -qF "ret ptr $allocation_result" <<<"$funnel_body"; then
  echo "regression: GC.malloc_atomic does not route through the slack allocator" >&2
  exit 1
fi
# Ignore unrelated fixed-size bookkeeping allocations in this function. The
# returned buffer must come from the padded allocator with the requested size.
if rg -q 'call ptr @(__adamas_malloc64|GC_malloc_atomic)\(i64 %size\)' <<<"$funnel_body"; then
  echo "regression: GC.malloc_atomic still allocates the exact size (slack bypassed)" >&2
  exit 1
fi

# String::Builder grows through GC.realloc; its libc branch needs the same slack.
realloc_body="$(fn_body 'define ptr @__adamas_gc_aware_realloc(')"
if [[ -z "$realloc_body" ]]; then
  echo "regression: @__adamas_gc_aware_realloc is not defined" >&2
  exit 1
fi
rg -q '%libc_slack = add i64 %size, 1' <<<"$realloc_body" || {
  echo "regression: @__adamas_gc_aware_realloc libc branch does not reserve slack" >&2
  exit 1
}
rg -q 'call ptr @__adamas_realloc64\(ptr %ptr, i64 %libc_slack\)' <<<"$realloc_body" || {
  echo "regression: native reallocation does not use the padded size" >&2
  exit 1
}

if ! "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 60 1024 >"$RUN_LOG" 2>&1; then
  echo "runtime failed (heap corruption from the one-byte overflow?)" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

rg -q 'nul_slack n=10400000' "$RUN_LOG" || {
  echo "regression: boundary-sized String.build produced the wrong payload" >&2
  cat "$RUN_LOG" >&2
  exit 1
}

echo "string_builder_nul_slack_ok"
