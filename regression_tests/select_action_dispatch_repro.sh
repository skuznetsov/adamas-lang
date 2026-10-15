#!/usr/bin/env bash
# Select uses Channel actions once, dispatches values, and preserves else results.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/select-action-dispatch.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
module SelectProbe
  @@created = 0
  @@received = 0

  def self.receive : Int32
    @@received += 1
    -1
  end

  def self.receive_select_action : Int32
    @@created += 1
    42
  end

  def self.created : Int32
    @@created
  end

  def self.received : Int32
    @@received
  end
end

# A deterministic adapter isolates compiler expansion from the scheduler.
class Channel(T)
  def self.select(ops : Tuple(Int32)) : Tuple(Int32, Int32)
    {0, ops[0]}
  end

  def self.non_blocking_select(ops : Tuple(Int32)) : Tuple(Int32, Int32)
    {-1, 0}
  end
end

result = select
when value = SelectProbe.receive
  value
end
puts result
puts SelectProbe.created
puts SelectProbe.received

result = select
when SelectProbe.receive
  99
else
  7
end
puts result
puts SelectProbe.created
puts SelectProbe.received

module SelectProbe
  @@arguments = 0

  def self.argument : Int32
    @@arguments += 1
    42
  end

  def self.send(value : Int32) : Int32
    @@received += 1
    -1
  end

  def self.send_select_action(value : Int32) : Int32
    @@created += 1
    value
  end

  def self.arguments : Int32
    @@arguments
  end
end

result = select
when SelectProbe.send(SelectProbe.argument)
  9
end
puts result
puts SelectProbe.created
puts SelectProbe.received
puts SelectProbe.arguments
CRYSTAL

cat >"$WORK_DIR/expected" <<'OUTPUT'
42
1
0
7
2
0
9
3
0
1
OUTPUT

compile_and_run() {
  local producer="$1"
  local compiler="$2"
  shift 2
  local bin="$WORK_DIR/$producer.bin"
  local cache_dir="$WORK_DIR/$producer.cache"
  local compile_log="$WORK_DIR/$producer.compile.log"
  local run_log="$WORK_DIR/$producer.run.log"
  local stdout="$WORK_DIR/$producer.stdout"
  local status=0

  mkdir -p "$cache_dir"
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$WORK_DIR/probe.cr" \
      -o "$bin" --link-flags=-fuse-ld=/usr/bin/ld >"$compile_log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$WORK_DIR/probe.cr" \
      --no-prelude --no-ast-cache --no-llvm-cache -o "$bin" >"$compile_log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]]; then
    cat "$compile_log" >&2
    return "$status"
  fi

  status=0
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.run.resources" \
    "$SAFE_RUNNER" "$bin" 15 512 >"$run_log" 2>&1 || status=$?
  if [[ "$status" != 0 ]] || ! grep -Fq '[EXIT: 0]' "$run_log"; then
    cat "$run_log" >&2
    return 1
  fi
  awk '
    $0 == "=== STDOUT ===" { in_stdout = 1; found = 1; next }
    $0 == "=== STDERR ===" { in_stdout = 0; done = 1; next }
    in_stdout { print }
    END { if (!found || !done) exit 2 }
  ' "$run_log" >"$stdout"
  diff -u "$WORK_DIR/expected" "$stdout"
}

compile_and_run original "$ORIGINAL_CRYSTAL_BIN"
compile_and_run candidate "$COMPILER"
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"
printf 'PASS: select actions, branch assignment, and else match Crystal\n'
