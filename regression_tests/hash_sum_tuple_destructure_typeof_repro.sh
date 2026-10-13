#!/usr/bin/env bash
# Regression for Hash#sum when the block receives a tuple and destructures it.
# The one-parameter tuple access is the control; the two-parameter block must
# preserve the same Int32/UInt16 value types while summing. UInt16 exercises
# an aligned primitive TypeId in self-hosted TypeRef array binding.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"
KEEP_TMP="${KEEP_TMP:-0}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_sum_tuple_destructure.XXXXXX")"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$WORK_DIR"
  else
    echo "kept test artifacts: $WORK_DIR"
  fi
}
trap cleanup EXIT

run_case() {
  local case_name="$1"
  local src="$WORK_DIR/$case_name.cr"
  local bin="$WORK_DIR/$case_name"
  local build_log="$WORK_DIR/$case_name.build.log"
  local run_log="$WORK_DIR/$case_name.run.log"

  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$case_name.build.resources" \
      "$SAFE_RUN" "$COMPILER" 300 8192 "$src" --no-llvm-cache -o "$bin" \
      >"$build_log" 2>&1; then
    echo "FAIL[$case_name]: compile failed" >&2
    tail -30 "$build_log" >&2
    return 1
  fi

  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$case_name.run.resources" \
      "$SAFE_RUN" "$bin" 5 512 >"$run_log" 2>&1; then
    echo "FAIL[$case_name]: runtime failed" >&2
    cat "$run_log" >&2
    return 1
  fi
  if ! grep -q '^\[EXIT: 0\]' "$run_log"; then
    echo "FAIL[$case_name]: expected a clean exit" >&2
    cat "$run_log" >&2
    return 1
  fi
}

cat >"$WORK_DIR/single_tuple.cr" <<'CR'
counts = {"a" => 1_i32, "b" => 2_i32}
total = counts.sum { |entry| entry[1] }
LibC.exit(total + 1_i32 == 4 ? 0 : 1)
CR

cat >"$WORK_DIR/destructured_tuple.cr" <<'CR'
counts = {"a" => 1_i32, "b" => 2_i32}
total = counts.sum { |_, value| value }
LibC.exit(total + 1_i32 == 4 ? 0 : 1)
CR

cat >"$WORK_DIR/single_tuple_u16.cr" <<'CR'
counts = {"a" => 1_u16, "b" => 2_u16}
total = counts.sum { |entry| entry[1] }
LibC.exit(total + 1_u16 == 4 ? 0 : 1)
CR

cat >"$WORK_DIR/destructured_tuple_u16.cr" <<'CR'
counts = {"a" => 1_u16, "b" => 2_u16}
total = counts.sum { |_, value| value }
LibC.exit(total + 1_u16 == 4 ? 0 : 1)
CR

run_case single_tuple
run_case destructured_tuple
run_case single_tuple_u16
run_case destructured_tuple_u16
echo "PASS: Hash#sum preserves Int32/UInt16 for tuple and destructured block parameters"
