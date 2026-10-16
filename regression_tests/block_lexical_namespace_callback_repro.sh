#!/usr/bin/env bash
# Full-prelude collection callbacks retain the caller lexical namespace.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexical-namespace-callback.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
lib CallbackC
  fun putchar(value : Int32) : Int32
end
class ProtectedCallbackOwner
  protected def load_apply(value : Int32) : Nil
    CallbackC.putchar(value)
    nil
  end
  def run(values : Hash(String, Array(Int32))) : Nil
    values.each_value &.each(&->self.load_apply(Int32))
    nil
  end
end
module CallbackMixin
  protected def load_apply(value : Int32) : Nil
    CallbackC.putchar(value)
    nil
  end
  def run(values : Hash(String, Array(Int32))) : Nil
    values.each_value &.each(&->self.load_apply(Int32))
    nil
  end
end
class ProtectedCallbackHost
  include CallbackMixin
end
ProtectedCallbackOwner.new.run({"outer" => [65]})
ProtectedCallbackHost.new.run({"outer" => [66]})
CallbackC.putchar(10)
CRYSTAL
printf 'AB\n' >"$WORK_DIR/expected.stdout"

cat >"$WORK_DIR/foreign.cr" <<'CRYSTAL'
class ProtectedCallbackOwner
  protected def load_apply(value : Int32) : Nil
    nil
  end
end

class ProtectedCallbackIntruder
  def run(owner : ProtectedCallbackOwner, values : Hash(String, Array(Int32))) : Nil
    values.each_value &.each(&->owner.load_apply(Int32))
    nil
  end
end

ProtectedCallbackIntruder.new.run(ProtectedCallbackOwner.new, {"outer" => [41]})
CRYSTAL

compile_and_check() {
  local producer="$1" source_name="$2" mode="$3"
  local bin="$WORK_DIR/$producer.$source_name.bin"
  local cache="$WORK_DIR/$producer.$source_name.cache"
  local build_log="$WORK_DIR/$producer.$source_name.build.log"
  local run_log="$WORK_DIR/$producer.$source_name.run.log"
  local stdout="$WORK_DIR/$producer.$source_name.stdout"
  local status=0
  mkdir -p "$cache"

  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.$source_name.build.resources" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/$source_name.cr" \
      -o "$bin" --no-debug --link-flags=-fuse-ld=/usr/bin/ld >"$build_log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.$source_name.build.resources" \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/$source_name.cr" \
      --no-debug --no-ast-cache --no-llvm-cache -o "$bin" >"$build_log" 2>&1 || status=$?
  fi

  if [[ "$mode" == reject ]]; then
    if [[ "$status" == 0 ]] || ! rg -q "protected method 'load_apply'" "$build_log"; then
      cat "$build_log" >&2
      echo "expected $producer to reject foreign protected callback access" >&2
      return 1
    fi
    return 0
  fi

  if [[ "$status" != 0 ]]; then
    cat "$build_log" >&2
    return "$status"
  fi

  status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.$source_name.run.resources" \
    "$SAFE_RUNNER" "$bin" 15 512 >"$stdout" 2>"$run_log" || status=$?
  if [[ "$status" != 0 ]] || ! rg -Fq '[EXIT: 0]' "$run_log"; then
    cat "$run_log" >&2
    return 1
  fi
  diff -u "$WORK_DIR/expected.stdout" "$stdout"
}

# Run the oracle first so a candidate-only failure cannot define the behavior.
compile_and_check original positive allow
compile_and_check candidate positive allow
diff -u "$WORK_DIR/original.positive.stdout" "$WORK_DIR/candidate.positive.stdout"
compile_and_check original foreign reject
compile_and_check candidate foreign reject

printf 'PASS: full-prelude lexical callbacks and foreign-owner rejection match Crystal\n'
