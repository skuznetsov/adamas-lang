#!/usr/bin/env bash
# Admit proven all-bottom generic class unions; keep unproven value joins guarded.
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-union-bottom.XXXXXX")"
cleanup() {
  local status=$?
  for name in bottom mixed rescued; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/bottom.cr" <<'CRYSTAL'
class HaltLeft(T)
  def default_result
    raise "member-left"
  end
  def stop(value : Int32)
    raise "call-left"
  end
  def wrapper
    stop(7)
  end
end
class HaltRight(T)
  def default_result
    raise "member-right"
  end
  def stop(value : Int32)
    raise "call-right"
  end
  def wrapper
    stop(7)
  end
end

def member_flow(flag : Bool)
  action = flag ? HaltLeft(Nil).new : HaltRight(Nil).new
  action.default_result
  puts "unreachable-member"
end

def call_flow(flag : Bool)
  action = flag ? HaltLeft(Nil).new : HaltRight(Nil).new
  action.stop(7)
  puts "unreachable-call"
end

def wrapper_flow(flag : Bool)
  action = flag ? HaltLeft(Nil).new : HaltRight(Nil).new
  action.wrapper
  puts "unreachable-wrapper"
end

begin
  member_flow(true)
rescue error
  puts error.message
end
begin
  member_flow(false)
rescue error
  puts error.message
end
begin
  call_flow(true)
rescue error
  puts error.message
end
begin
  call_flow(false)
rescue error
  puts error.message
end
begin
  wrapper_flow(true)
rescue error
  puts error.message
end
begin
  wrapper_flow(false)
rescue error
  puts error.message
end
CRYSTAL
printf 'member-left\nmember-right\ncall-left\ncall-right\ncall-left\ncall-right\n' >"$WORK_DIR/bottom.expected"

cat >"$WORK_DIR/mixed.cr" <<'CRYSTAL'
class HaltArm(T)
  def default_result
    raise "halted"
  end
end
class ReturnArm(T)
  def default_result
    "returned"
  end
end
def returning_flow(flag : Bool)
  action = flag ? HaltArm(Nil).new : ReturnArm(Nil).new
  result = action.default_result
  puts result
  puts "after"
end
begin
  returning_flow(true)
rescue error
  puts error.message
end
returning_flow(false)
CRYSTAL
printf 'halted\nreturned\nafter\n' >"$WORK_DIR/mixed.expected"

cat >"$WORK_DIR/rescued.cr" <<'CRYSTAL'
class RaisedArm(T)
  def default_result
    raise "raised"
  end
end
class RescuedArm(T)
  def default_result
    begin
      raise "rescued"
    rescue error
      error.message || "missing"
    end
  end
end
def rescued_flow(flag : Bool)
  action = flag ? RaisedArm(Nil).new : RescuedArm(Nil).new
  result = action.default_result
  puts result
  puts "after-rescue"
end
begin
  rescued_flow(true)
rescue error
  puts error.message
end
rescued_flow(false)
CRYSTAL
printf 'raised\nrescued\nafter-rescue\n' >"$WORK_DIR/rescued.expected"

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

# All six runtime branches must agree with the original compiler.
compile_and_run_positive bottom "$ORIGINAL_CRYSTAL_BIN" original
compile_and_run_positive bottom "$COMPILER" candidate
echo 'PASS[bottom]: six original-first member, positional and wrapper outputs agree'

# These original-valid shapes remain unsupported until their return carrier is
# certified. Rejection is a guard check, not a compatibility success claim.
for name in mixed rescued; do
  compile_and_run_positive "$name" "$ORIGINAL_CRYSTAL_BIN" original
  status=0
  env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate-$name.cache" \
    ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate-$name.compile.resources" \
    "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/$name.cr" \
    --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/candidate-$name.bin" \
    >"$WORK_DIR/candidate-$name.compile.log" 2>&1 || status=$?
  if [[ "$status" -ne 1 || -e "$WORK_DIR/candidate-$name.bin" ]] || \
     ! grep -Fq 'cannot safely lower unresolved returns for concrete generic receiver union' \
       "$WORK_DIR/candidate-$name.compile.log"; then
    echo "FAIL[guard/$name]: unsupported return join was admitted or failed unexpectedly" >&2
    tail -30 "$WORK_DIR/candidate-$name.compile.log" >&2
    exit 1
  fi
  echo "PASS[guard/$name]: unsupported value join remains rejected"
done
echo 'PASS[generic-union-bottom]: six matching outputs and two retained value-join guards'
