#!/usr/bin/env bash
# A block stored by an initializer must retain the receiver environment after
# the receiver method returns. The paired receivers also ensure each callback
# owns its own environment rather than sharing or overwriting capture state.
#
# Usage: ADAMAS_BIN=path/to/adamas ORIGINAL_CRYSTAL_BIN=path/to/crystal \
#   CRYSTAL_PATH=/path/to/crystal/src $0
# Set ORACLE_ONLY=1 to qualify the fixtures against installed Crystal without
# invoking the Adamas compiler.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-/opt/homebrew/opt/crystal/bin/crystal}}"
CRYSTAL_PATH="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
ORACLE_ONLY="${ORACLE_ONLY:-0}"

if [[ ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -x "$SAFE_RUNNER" || ! -d "$CRYSTAL_PATH" || \
      ( "$ORACLE_ONLY" != 1 && ! -x "$ADAMAS_BIN" ) ]]; then
  printf 'usage: ADAMAS_BIN=<compiler> ORIGINAL_CRYSTAL_BIN=<crystal> CRYSTAL_PATH=<stdlib> %s\n' "$0" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stored-block-capture-lifetime.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$WORK_DIR"
  fi
}
trap cleanup EXIT

# These no-prelude fixtures avoid runtime threads and encode each observed
# callback result in the process exit status, so wrong or aliased captures are
# rejected by an exact payload comparison.
COMMON_SOURCE='@[Link("gc", pkg_config: "bdw-gc")]
lib StoredBlockCaptureLibC
  fun _exit(status : Int32) : NoReturn
end

class StoredBlockCaptureHolder
  @callback : Proc(Int32)

  def initialize(&@callback : -> Int32)
  end

  def call : Int32
    @callback.call
  end
end

class StoredBlockCaptureProcLiteralHolder
  @callback : Proc(Int32)

  def initialize(@callback : Proc(Int32))
  end

  def call : Int32
    @callback.call
  end
end

class StoredBlockCaptureMixedHolder
  @callback : Proc(Int32)
  @initial : Int32

  def initialize(&@callback : -> Int32)
    @initial = yield
  end

  def initial : Int32
    @initial
  end

  def call : Int32
    @callback.call
  end
end

class StoredBlockCaptureYieldOnlyHolder
  @initial : Int32

  def initialize(&block : -> Int32)
    @initial = yield
  end

  def initial : Int32
    @initial
  end
end

class StoredBlockCaptureProcBeforeBlockHolder
  @decoy : Proc(Int32)
  @callback : Proc(Int32)
  @initial : Int32

  def initialize(decoy : Proc(Int32), &@callback : -> Int32)
    @decoy = decoy
    @initial = yield
  end

  def decoy_call : Int32
    @decoy.call
  end

  def initial : Int32
    @initial
  end

  def callback_call : Int32
    @callback.call
  end
end

class StoredBlockCaptureUnionHolder
  @callback : Proc(Int32?, Int32?)
  @initial : Int32?

  def initialize(&@callback : Int32? -> Int32?)
    @initial = yield 17
  end

  def initial : Int32?
    @initial
  end

  def call(value : Int32?) : Int32?
    @callback.call(value)
  end
end

class StoredBlockCaptureParent
  def value : Int32
    29
  end
end

class StoredBlockCaptureChild < StoredBlockCaptureParent
end

class StoredBlockCaptureSubtypeHolder
  @callback : Proc(StoredBlockCaptureParent, Int32)
  @initial : Int32

  def initialize(&@callback : StoredBlockCaptureParent -> Int32)
    @initial = yield StoredBlockCaptureChild.new
  end

  def initial : Int32
    @initial
  end

  def call(value : StoredBlockCaptureParent) : Int32
    @callback.call(value)
  end
end

class StoredBlockCaptureReceiver
  @value : Int32

  def initialize(@value : Int32)
  end

  def value : Int32
    @value
  end

  def holder : StoredBlockCaptureHolder
    StoredBlockCaptureHolder.new { @value }
  end

  def explicit_holder : StoredBlockCaptureHolder
    StoredBlockCaptureHolder.new { self.value }
  end

  def proc_literal_holder : StoredBlockCaptureProcLiteralHolder
    StoredBlockCaptureProcLiteralHolder.new(-> { @value })
  end

  def mixed_holder : StoredBlockCaptureMixedHolder
    StoredBlockCaptureMixedHolder.new { @value }
  end

  def yield_only_holder : StoredBlockCaptureYieldOnlyHolder
    StoredBlockCaptureYieldOnlyHolder.new { @value }
  end
end

def make_receiver(value : Int32) : StoredBlockCaptureReceiver
  StoredBlockCaptureReceiver.new(value)
end

def make_implicit_holder(value : Int32) : StoredBlockCaptureHolder
  make_receiver(value).holder
end

def make_explicit_holder(value : Int32) : StoredBlockCaptureHolder
  make_receiver(value).explicit_holder
end

def make_proc_literal_holder(value : Int32) : StoredBlockCaptureProcLiteralHolder
  make_receiver(value).proc_literal_holder
end

def make_proc_before_block_holder(value : Int32, decoy : Proc(Int32)) : StoredBlockCaptureProcBeforeBlockHolder
  StoredBlockCaptureProcBeforeBlockHolder.new(decoy) { value }
end
'

write_case() {
  local name="$1"
  local body="$2"
  printf '%s\n%s\n' "$COMMON_SOURCE" "$body" >"$WORK_DIR/$name.cr"
}

write_case stored_implicit '
holder = make_implicit_holder(17)
StoredBlockCaptureLibC._exit(holder.call)'

write_case stored_explicit_self '
holder = make_explicit_holder(29)
StoredBlockCaptureLibC._exit(holder.call)'

write_case distinct_receiver_environments '
first = make_implicit_holder(17)
second = make_implicit_holder(29)
StoredBlockCaptureLibC._exit(first.call &+ (second.call &* 2))'

write_case proc_literal_control '
holder = make_proc_literal_holder(29)
StoredBlockCaptureLibC._exit(holder.call)'

write_case stored_and_yielded '
holder = make_receiver(17).mixed_holder
StoredBlockCaptureLibC._exit(holder.initial &+ (holder.call &* 2))'

write_case yield_only_control '
holder = make_receiver(29).yield_only_holder
StoredBlockCaptureLibC._exit(holder.initial)'

write_case stored_regular_proc_before_block '
decoy = -> { 11 }
holder = make_proc_before_block_holder(29, decoy)
payload = holder.initial &+ (holder.callback_call &* 2) &+ (holder.decoy_call &* 4)
StoredBlockCaptureLibC._exit(payload)'

write_case stored_union_callback '
holder = StoredBlockCaptureUnionHolder.new { |value| value }
first = holder.initial || 0
second = holder.call(29) || 0
if holder.call(nil)
  StoredBlockCaptureLibC._exit(99)
end
StoredBlockCaptureLibC._exit(first &+ (second &* 2))'

write_case stored_subtype_callback '
holder = StoredBlockCaptureSubtypeHolder.new { |value| value.value }
StoredBlockCaptureLibC._exit(holder.initial &+ (holder.call(StoredBlockCaptureChild.new) &* 2))'

write_case wrong_yield_input '
class StoredBlockCaptureWrongYieldInput
  @callback : Proc(Int32, Int32)
  @initial : Int32

  def initialize(decoy : Proc(Int32), &@callback : Int32 -> Int32)
    @initial = yield("wrong")
  end
end

decoy = -> { 11 }
StoredBlockCaptureWrongYieldInput.new(decoy) { |value| value }'

write_case wrong_nullable_yield_input '
class StoredBlockCaptureWrongNullableYieldInput
  @callback : Proc(Int32?, Int32?)
  @initial : Int32?

  def initialize(&@callback : Int32? -> Int32?)
    @initial = yield("wrong")
  end
end

StoredBlockCaptureWrongNullableYieldInput.new { |value| value }'

write_case wrong_callback_result '
class StoredBlockCaptureWrongCallbackResult
  @callback : Proc(Int32)
  @initial : Int32

  def initialize(decoy : Proc(Int32), &@callback : -> Int32)
    @initial = yield
  end
end

decoy = -> { 11 }
StoredBlockCaptureWrongCallbackResult.new(decoy) { "wrong" }'

CASES=(stored_implicit:17 stored_explicit_self:29 distinct_receiver_environments:75 proc_literal_control:29 stored_and_yielded:51 yield_only_control:29 stored_regular_proc_before_block:131 stored_union_callback:75 stored_subtype_callback:87)

exit_code_of() {
  grep -oE '\[EXIT: [0-9]+\]' "$1" | tail -1 | tr -dc '0-9'
}

run_fixture() {
  local producer="$1"
  local name="$2"
  local expected="$3"
  local case_dir="$WORK_DIR/$name.$producer"
  local binary="$case_dir/probe"
  local compile_log="$case_dir.compile.log"
  local run_log="$case_dir.run.log"
  mkdir -p "$case_dir/cache"

  if [[ "$producer" == original ]]; then
    if ! env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$case_dir/cache" \
        "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/$name.cr" \
        --prelude=empty -o "$binary" --link-flags=-fuse-ld=/usr/bin/ld >"$compile_log" 2>&1; then
      printf 'ORACLE COMPILE FAIL: %s\n' "$name" >&2
      cat "$compile_log" >&2
      return 1
    fi
  else
    if ! env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$case_dir/cache" \
        ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
        "$SAFE_RUNNER" "$ADAMAS_BIN" 180 8192 "$WORK_DIR/$name.cr" \
        --prelude=empty --no-ast-cache --no-llvm-cache -o "$binary" >"$compile_log" 2>&1; then
      printf 'ADAMAS COMPILE FAIL: %s\n' "$name" >&2
      cat "$compile_log" >&2
      return 1
    fi
  fi

  "$SAFE_RUNNER" "$binary" 10 512 >"$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" != "$expected" ]]; then
    printf '%s RUN FAIL: %s exited %s, expected exact payload %s\n' \
      "$producer" "$name" "$(exit_code_of "$run_log")" "$expected" >&2
    cat "$run_log" >&2
    return 1
  fi
  printf 'PASS %s %s (exit payload %s)\n' "$producer" "$name" "$expected"
}

expect_compile_rejection() {
  local producer="$1"
  local name="$2"
  local case_dir="$WORK_DIR/$name.$producer"
  local compile_log="$case_dir.compile.log"
  local context_pattern
  mkdir -p "$case_dir/cache"

  case "$name" in
    wrong_yield_input|wrong_nullable_yield_input) context_pattern='Proc|yield|argument|expected' ;;
    wrong_callback_result) context_pattern='block|callback|Proc|return|expected' ;;
    *)
      printf 'unknown negative fixture: %s\n' "$name" >&2
      return 2
      ;;
  esac

  if [[ "$producer" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$case_dir/cache" \
        "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/$name.cr" \
        --prelude=empty -o "$case_dir/probe" --link-flags=-fuse-ld=/usr/bin/ld >"$compile_log" 2>&1; then
      printf 'ORACLE ACCEPTED NEGATIVE FIXTURE: %s\n' "$name" >&2
      return 1
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$case_dir/cache" \
        ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
        "$SAFE_RUNNER" "$ADAMAS_BIN" 180 8192 "$WORK_DIR/$name.cr" \
        --prelude=empty --no-ast-cache --no-llvm-cache -o "$case_dir/probe" >"$compile_log" 2>&1; then
      printf 'ADAMAS ACCEPTED NEGATIVE FIXTURE: %s\n' "$name" >&2
      return 1
    fi
  fi

  if [[ "$(exit_code_of "$compile_log")" != 1 || -e "$case_dir/probe" ]] || \
      ! grep -q 'Int32' "$compile_log" || ! grep -q 'String' "$compile_log" || \
      ! grep -Eq "$context_pattern" "$compile_log"; then
    printf '%s NEGATIVE FIXTURE FAILED FOR AN UNRELATED REASON: %s\n' "$producer" "$name" >&2
    cat "$compile_log" >&2
    return 1
  fi
  printf 'PASS %s rejects %s with Int32/String type diagnostic\n' "$producer" "$name"
}

# Qualify every fixture against the currently installed original compiler
# before invoking the candidate. No particular Crystal version is required.
if ! "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 5 256 --version >"$WORK_DIR/original.version.log" 2>&1; then
  printf 'ORACLE VERSION CHECK FAIL\n' >&2
  cat "$WORK_DIR/original.version.log" >&2
  exit 1
fi

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  run_fixture original "$name" "$expected"
done

for name in wrong_yield_input wrong_nullable_yield_input wrong_callback_result; do
  expect_compile_rejection original "$name"
done

if [[ "$ORACLE_ONLY" == 1 ]]; then
  printf 'installed Crystal oracle qualification passed\n'
  exit 0
fi

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  run_fixture adamas "$name" "$expected"
done

for name in wrong_yield_input wrong_nullable_yield_input wrong_callback_result; do
  expect_compile_rejection adamas "$name"
done

printf 'stored block receiver capture lifetime cases passed\n'
