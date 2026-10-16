#!/usr/bin/env bash
# Preserve nullable arrow Proc source restrictions without weakening input or result checks.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
elif [[ -d "$ROOT_DIR/../crystal/src" ]]; then
  CRYSTAL_STDLIB="$(cd "$ROOT_DIR/../crystal/src" && pwd -P)"
else
  echo "set CRYSTAL_PATH to the external Crystal stdlib source directory" >&2
  exit 2
fi

[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "candidate, original Crystal, SAFE runner, or external stdlib is unavailable" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nullable-proc-source.XXXXXX")"
cleanup() {
  local status=$?
  for name in callback bad_input bad_arity bad_result; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

# Source restriction spelling must retain the same Proc signature and unions.
cat >"$WORK_DIR/callback.cr" <<'CRYSTAL'
module CallbackScope
  class Server
    class Context
    end
    def self.nullable(number : Int32, callback : (Context ->)? = nil)
      callback.nil?
    end
    def self.discard(callback : (Context ->)?)
      callback.nil?
    end
    def self.typed(callback : (Context -> Int32)?)
      callback.nil?
    end
    def self.multiple(callback : (Context, Int32 -> String)?)
      callback.nil?
    end
    def self.nested(callbacks : Array((Context ->)))
      callbacks.size
    end
  end
end

def route_callback(flag : Bool)
  callback = flag ? ->(context : CallbackScope::Server::Context) { nil } : nil
  CallbackScope::Server.nullable(1, callback)
end
puts route_callback(true)
puts route_callback(false)
puts CallbackScope::Server.discard(->(context : CallbackScope::Server::Context) { 17 })
puts CallbackScope::Server.typed(->(context : CallbackScope::Server::Context) { 17 })
puts CallbackScope::Server.typed(nil)
puts CallbackScope::Server.multiple(->(context : CallbackScope::Server::Context, number : Int32) { number.to_s })
puts CallbackScope::Server.nested([->(context : CallbackScope::Server::Context) { nil }])
puts CallbackScope::Server.nullable(1)
CRYSTAL
printf 'false\ntrue\nfalse\nfalse\ntrue\nfalse\n1\ntrue\n' >"$WORK_DIR/callback.expected"

for name in bad_input bad_arity bad_result; do
  cat >"$WORK_DIR/$name.cr" <<'CRYSTAL'
module CallbackScope
  class Server
    class Context
    end
    def self.accept(callback : (Context -> Int32)?)
      callback.nil?
    end
  end
end
CRYSTAL
done
cat >>"$WORK_DIR/bad_input.cr" <<'CRYSTAL'
puts CallbackScope::Server.accept(->(context : Int32) { 17 })
CRYSTAL
cat >>"$WORK_DIR/bad_arity.cr" <<'CRYSTAL'
puts CallbackScope::Server.accept(->(context : CallbackScope::Server::Context, extra : Int32) { 17 })
CRYSTAL
cat >>"$WORK_DIR/bad_result.cr" <<'CRYSTAL'
puts CallbackScope::Server.accept(->(context : CallbackScope::Server::Context) { "wrong" })
CRYSTAL

compile_and_run_positive() {
  local name="$1" compiler="$2" mode="$3" status=0
  local source="$WORK_DIR/$name.cr" output="$WORK_DIR/$mode-$name.bin"
  local log="$WORK_DIR/$mode-$name.compile.log"
  local cache="$WORK_DIR/$mode-$name.cache"
  if [[ "$mode" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$source" --no-debug \
      --link-flags=-fuse-ld=/usr/bin/ld -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-ast-cache --no-llvm-cache \
      --no-debug -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$mode/$name]: compile exited $status" >&2
    tail -30 "$log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.run.resources" \
    "$SAFE_RUNNER" "$output" 10 512 >"$WORK_DIR/$mode-$name.stdout" \
    2>"$WORK_DIR/$mode-$name.run.log"; then
    echo "FAIL[$mode/$name]: runtime failed" >&2
    cat "$WORK_DIR/$mode-$name.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$mode-$name.run.log" || {
    cat "$WORK_DIR/$mode-$name.run.log" >&2
    return 1
  }
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$mode-$name.stdout"
}

compile_and_reject() {
  local name="$1" compiler="$2" mode="$3" status=0
  local log="$WORK_DIR/$mode-$name.compile.log" cache="$WORK_DIR/$mode-$name.cache"
  if [[ "$mode" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$compiler" 60 8192 build "$WORK_DIR/$name.cr" --no-debug \
      --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK_DIR/$mode-$name.bin" >"$log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      "$SAFE_RUNNER" "$compiler" 60 8192 "$WORK_DIR/$name.cr" --no-ast-cache --no-llvm-cache \
      --no-debug -o "$WORK_DIR/$mode-$name.bin" >"$log" 2>&1 || status=$?
  fi
  if [[ "$status" -ne 1 ]]; then
    echo "FAIL[$mode/$name]: expected semantic rejection, got $status" >&2
    tail -30 "$log" >&2
    return 1
  fi
  if [[ "$mode" == original ]]; then
    grep -Fq 'Error:' "$log" || { cat "$log" >&2; return 1; }
  else
    grep -Fq 'no overload matches CallbackScope::Server.accept' "$log" || { cat "$log" >&2; return 1; }
  fi
}

compile_and_run_positive callback "$ORIGINAL_CRYSTAL_BIN" original
compile_and_run_positive callback "$COMPILER" candidate
echo 'PASS[callback]: eight namespace, union, discard, explicit-result, nested and default controls agree'
for name in bad_input bad_arity bad_result; do
  compile_and_reject "$name" "$ORIGINAL_CRYSTAL_BIN" original
  compile_and_reject "$name" "$COMPILER" candidate
  echo "PASS[$name]: original and candidate reject the incompatible Proc restriction"
done
