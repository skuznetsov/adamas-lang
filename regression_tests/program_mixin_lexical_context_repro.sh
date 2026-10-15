#!/usr/bin/env bash
# Program mixins retain their lexical namespace and visibility restrictions.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/program-mixin-context.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

write_probe() {
  local name="$1" operation="$2" receiver="$3" namespace="$4" visibility="$5"
  cat >"$WORK_DIR/$name.cr" <<CRYSTAL
module Guarded
  class Context
    $visibility def answer : Int32
      42
    end
  end
end
module $namespace
  module Methods
    def guarded_answer : Int32
      $receiver.new.answer
    end
  end
end
$operation $namespace::Methods
puts guarded_answer
CRYSTAL
}

write_probe include include Guarded::Context Guarded protected
write_probe extend extend Guarded::Context Guarded protected
write_probe relative include Context Guarded protected
write_probe unrelated include Guarded::Context Unrelated protected
write_probe private include Guarded::Context Guarded private
printf '42\n' >"$WORK_DIR/expected"

check_probe() {
  local producer="$1" name="$2" expectation="$3"
  local bin="$WORK_DIR/$producer.$name.bin"
  local cache_dir="$WORK_DIR/$producer.$name.cache"
  local compile_log="$WORK_DIR/$producer.$name.compile.log"
  local run_log="$WORK_DIR/$producer.$name.run.log"
  local stdout="$WORK_DIR/$producer.$name.stdout"
  local status=0
  mkdir -p "$cache_dir"

  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.$name.compile.resources" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/$name.cr" \
      -o "$bin" --link-flags=-fuse-ld=/usr/bin/ld >"$compile_log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.$name.compile.resources" \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/$name.cr" \
      --no-prelude --no-ast-cache --no-llvm-cache -o "$bin" >"$compile_log" 2>&1 || status=$?
  fi
  if [[ "$expectation" != allow ]]; then
    if [[ "$status" == 0 ]] || ! rg -q "$expectation method .*answer" "$compile_log"; then
      cat "$compile_log" >&2
      echo "expected $producer to reject $name visibility" >&2
      return 1
    fi
    return
  fi
  if [[ "$status" != 0 ]]; then
    cat "$compile_log" >&2
    return "$status"
  fi

  status=0
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.$name.run.resources" \
    "$SAFE_RUNNER" "$bin" 15 512 >"$run_log" 2>&1 || status=$?
  if [[ "$status" != 0 ]] || ! rg -Fq '[EXIT: 0]' "$run_log"; then
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

for producer in original candidate; do
  check_probe "$producer" include allow
  check_probe "$producer" extend allow
  check_probe "$producer" relative allow
  check_probe "$producer" unrelated protected
  check_probe "$producer" private private
done
printf 'PASS: Program mixin lexical access and both visibility guards match Crystal\n'
