#!/usr/bin/env bash
# A deep generic class-method chain must retain the leaf's exact return type.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-180}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
ONLY_CASES="${ONLY_CASES:-all}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
CHAIN_DEPTH="${CHAIN_DEPTH:-8}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--lgc -fuse-ld=/usr/bin/ld}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/force-depth-return-dependency.XXXXXX")"

cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache-*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ "$ORIGINAL_ONLY" != 0 && "$ORIGINAL_ONLY" != 1 ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ ! "$CHAIN_DEPTH" =~ ^[1-9][0-9]*$ ]] || (( CHAIN_DEPTH > 512 )); then
  echo "ERROR: CHAIN_DEPTH must be an integer from 1 through 512" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -d "$CRYSTAL_STDLIB" ]]; then
  echo "ERROR: safe runner, original Crystal, or stock Crystal stdlib is unavailable" >&2
  echo "Usage: ORIGINAL_ONLY=1 CRYSTAL_PATH=/path/to/crystal/src ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0" >&2
  exit 2
fi
if [[ ! -f "$CRYSTAL_STDLIB/empty.cr" ]]; then
  echo "ERROR: CRYSTAL_PATH must name the stock Crystal src directory (missing empty.cr)" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != 1 && ! -x "$ADAMAS_BIN" ]]; then
  echo "ERROR: candidate Adamas compiler is unavailable" >&2
  echo "Usage: ADAMAS_BIN=/path/to/adamas ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0" >&2
  exit 2
fi

ALL_CASES=(payload int32 pointer nilable_payload sibling_shapes captured_provisional
  member_new_dependency member_new_dependency_parens member_direct_result)
if [[ "$ONLY_CASES" == all ]]; then
  SELECTED_CASES=("${ALL_CASES[@]}")
else
  normalized_cases="${ONLY_CASES//,/ }"
  read -r -a SELECTED_CASES <<<"$normalized_cases"
  if [[ "${#SELECTED_CASES[@]}" -eq 0 ]]; then
    echo "ERROR: ONLY_CASES must be all or a comma/space-separated case list" >&2
    exit 2
  fi
  for selected in "${SELECTED_CASES[@]}"; do
    known=0
    for available in "${ALL_CASES[@]}"; do
      [[ "$selected" == "$available" ]] && known=1
    done
    if [[ "$known" != 1 ]]; then
      printf 'ERROR: unknown ONLY_CASES entry: %s\nAvailable: %s\n' \
        "$selected" "${ALL_CASES[*]}" >&2
      exit 2
    fi
  done
fi
if (( CHAIN_DEPTH < 4 )); then
  for selected in "${SELECTED_CASES[@]}"; do
    if [[ "$selected" == captured_provisional ]]; then
      echo "ERROR: captured_provisional requires CHAIN_DEPTH of at least 4" >&2
      exit 2
    fi
  done
fi

write_factory0() {
  local name="$1"
  case "$name" in
    payload|captured_provisional)
      cat <<'CRYSTAL'
class ForceDepthFactory0
  def self.new(value : T) forall T
    ForceDepthPayload.new
  end
end
CRYSTAL
      ;;
    int32)
      cat <<'CRYSTAL'
class ForceDepthFactory0
  def self.new(value : T) forall T
    value &+ 64
  end
end
CRYSTAL
      ;;
    pointer)
      cat <<'CRYSTAL'
class ForceDepthFactory0
  def self.new(value : T) forall T
    ForceDepthNative.malloc(1_u64)
  end
end
CRYSTAL
      ;;
    nilable_payload|sibling_shapes)
      cat <<'CRYSTAL'
class ForceDepthFactory0
  def self.new(value : T) forall T
    value
  end
end
CRYSTAL
      ;;
  esac
}

write_source() {
  local name="$1"
  local path="$WORK_DIR/$name.cr"
  case "$name" in
    member_*)
      # The first replay discovers the concrete merge overload only after
      # measurements settles. Its result is a second exact dependency.
      cat >"$path" <<'CRYSTAL'
require "named_tuple"
@[Link("gc")]
lib LibC
  fun putchar(value : Int32) : Int32
end

class Stats
  @code : Int32

  def initialize(@code : Int32)
  end

  def details
    {code: @code}
  end

  def sample(&)
    yield @code
  end

  def measurements
    count = 0_u64
    sample { |x| count = x.to_u64! }
    {measurements: {count: count}}
  end
end

struct View
  def initialize(@stats : Stats)
  end

  def details
    @stats.details.merge(@stats.measurements)
  end
end

def show_stats(tuple : NamedTuple)
  LibC.putchar(tuple[:code])
  LibC.putchar(tuple[:measurements][:count] == 65_u64 ? 85 : 88)
end

def once(&)
  yield
end

def show(view : View)
  once { show_stats(view.details) }
end

show(View.new(Stats.new(65)))
LibC.putchar(10)
CRYSTAL
      if [[ "$name" == member_new_dependency_parens ]]; then
        sed 's/show_stats(view.details)/show_stats(view.details())/' "$path" >"$path.expanded"
        mv -- "$path.expanded" "$path"
      elif [[ "$name" == member_direct_result ]]; then
        sed 's/once { show_stats(view.details) }/show_stats(view.details)/' "$path" >"$path.expanded"
        mv -- "$path.expanded" "$path"
      fi
      return
      ;;
  esac
  cat >"$path" <<'CRYSTAL'
@[Link("c")]
lib ForceDepthNative
  fun putchar(value : Int32) : Int32
  fun malloc(size : UInt64) : Pointer(UInt8)
  fun free(pointer : Pointer(UInt8)) : Void
end

class ForceDepthPayload
  def marker : Int32
    112
  end
end
CRYSTAL

  write_factory0 "$name" >>"$path"
  for ((depth = 1; depth <= CHAIN_DEPTH; depth++)); do
    previous=$((depth - 1))
    if [[ "$name" == captured_provisional && "$depth" == 4 ]]; then
      cat >>"$path" <<'CRYSTAL'
class ForceDepthFactory4
  def self.new(value : T) forall T
    marker = 65
    mutator = -> { marker = 66 }
    result = ForceDepthFactory3.new(value)
    mutator.call
    ForceDepthNative.putchar(marker)
    result
  end
end
CRYSTAL
    else
      printf 'class ForceDepthFactory%s\n  def self.new(value : T) forall T\n    ForceDepthFactory%s.new(value)\n  end\nend\n' \
        "$depth" "$previous" >>"$path"
    fi
  done

  case "$name" in
    payload|captured_provisional)
      cat >>"$path" <<'CRYSTAL'
class ForceDepthSink
  def self.pick(value : ForceDepthPayload) : Int32; 80; end
  def self.pick(value : Int32) : Int32; 73; end
end
value = ForceDepthFactory__DEPTH__.new(1)
ForceDepthNative.putchar(ForceDepthSink.pick(value))
ForceDepthNative.putchar(value.marker)
CRYSTAL
      ;;
    int32)
      cat >>"$path" <<'CRYSTAL'
class ForceDepthSink
  def self.pick(value : Int32) : Int32; 73; end
  def self.pick(value : Bool) : Int32; 66; end
end
value = ForceDepthFactory__DEPTH__.new(1)
ForceDepthNative.putchar(ForceDepthSink.pick(value))
ForceDepthNative.putchar(value)
CRYSTAL
      ;;
    pointer)
      cat >>"$path" <<'CRYSTAL'
class ForceDepthSink
  def self.pick(value : Pointer(UInt8)) : Int32; 82; end
  def self.pick(value : UInt8) : Int32; 86; end
end
pointer = ForceDepthFactory__DEPTH__.new(1)
ForceDepthNative.putchar(ForceDepthSink.pick(pointer))
ForceDepthNative.free(pointer)
CRYSTAL
      ;;
    nilable_payload)
      cat >>"$path" <<'CRYSTAL'
class ForceDepthSink
  def self.pick(value : ForceDepthPayload?) : Int32; 78; end
end
def force_depth_optional(flag : Bool) : ForceDepthPayload?
  if flag
    ForceDepthPayload.new
  else
    nil
  end
end
present = ForceDepthFactory__DEPTH__.new(force_depth_optional(true))
ForceDepthNative.putchar(ForceDepthSink.pick(present))
if present
  ForceDepthNative.putchar(present.marker)
else
  ForceDepthNative.putchar(90)
end
absent = ForceDepthFactory__DEPTH__.new(force_depth_optional(false))
ForceDepthNative.putchar(ForceDepthSink.pick(absent))
if absent
  ForceDepthNative.putchar(absent.marker)
else
  ForceDepthNative.putchar(110)
end
CRYSTAL
      ;;
    sibling_shapes)
      cat >>"$path" <<'CRYSTAL'
class ForceDepthSink
  def self.pick(value : Int32) : Int32; 73; end
  def self.pick(value : Bool) : Int32; 66; end
end
integer = ForceDepthFactory__DEPTH__.new(65)
boolean = ForceDepthFactory__DEPTH__.new(true)
ForceDepthNative.putchar(ForceDepthSink.pick(integer))
ForceDepthNative.putchar(integer)
ForceDepthNative.putchar(ForceDepthSink.pick(boolean))
if boolean
  ForceDepthNative.putchar(67)
else
  ForceDepthNative.putchar(68)
end
CRYSTAL
      ;;
  esac
  sed "s/ForceDepthFactory__DEPTH__/ForceDepthFactory${CHAIN_DEPTH}/g" \
    "$path" >"$path.expanded"
  mv -- "$path.expanded" "$path"
  printf 'ForceDepthNative.putchar(10)\n' >>"$path"
}

compile_one() {
  local stage="$1" name="$2" compiler="$3"
  local binary="$WORK_DIR/$stage-$name.bin"
  local log="$WORK_DIR/$stage-$name.build.log"
  local cache="$WORK_DIR/cache-$stage-$name"
  local status=0
  local -a command mode_env=()
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    command=(build --prelude=empty --no-debug "$WORK_DIR/$name.cr" -o "$binary" \
      "--link-flags=$LINK_FLAGS")
  else
    command=("$WORK_DIR/$name.cr" --no-prelude --no-debug --no-ast-cache \
      --no-llvm-cache -o "$binary")
    if [[ "$stage" == candidate-eager ]]; then
      mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    else
      mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    fi
  fi

  if [[ "$stage" == original ]]; then
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "${command[@]}" >"$log" 2>&1 || status=$?
  else
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" \
      "${mode_env[@]}" "$SAFE_RUNNER" "$compiler" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" "${command[@]}" >"$log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]] || ! rg -q '^\[EXIT: 0\]( |$)' "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: compile did not exit zero\n' "$stage" "$name" >&2
    return 1
  fi
  rm -rf -- "$cache"
  printf '%s\n' "$binary"
}

run_binary() {
  local stage="$1" name="$2" binary="$3" expected="$4"
  local stdout="$WORK_DIR/$stage-$name.stdout"
  local log="$WORK_DIR/$stage-$name.run.log"
  local status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.resources.json" \
    "$SAFE_RUNNER" "$binary" 10 1024 >"$stdout" 2>"$log" || status=$?
  if [[ "$status" != 0 ]] || ! rg -q '^\[EXIT: 0\]( |$)' "$log"; then
    cat "$log" >&2
    cat "$stdout" >&2
    printf 'FAIL %s %s: native run did not exit zero\n' "$stage" "$name" >&2
    return 1
  fi
  printf '%s\n' "$expected" >"$WORK_DIR/$name.expected"
  if ! diff -u "$WORK_DIR/$name.expected" "$stdout"; then
    printf 'FAIL %s %s: stdout differed from expected output\n' "$stage" "$name" >&2
    return 1
  fi
  if [[ "$stage" != original ]] && ! diff -u "$WORK_DIR/original-$name.stdout" "$stdout"; then
    printf 'FAIL %s %s: stdout differed from original Crystal\n' "$stage" "$name" >&2
    return 1
  fi
  printf 'PASS %s %s output=%q\n' "$stage" "$name" "$expected"
}

for name in "${SELECTED_CASES[@]}"; do
  write_source "$name"
  case "$name" in
    payload) expected=Pp ;;
    int32) expected=IA ;;
    pointer) expected=R ;;
    nilable_payload) expected=NpNn ;;
    sibling_shapes) expected=IABC ;;
    captured_provisional) expected=BPp ;;
    member_*) expected=AU ;;
  esac

  binary="$(compile_one original "$name" "$ORIGINAL_CRYSTAL_BIN")"
  run_binary original "$name" "$binary" "$expected"
  if [[ "$ORIGINAL_ONLY" == 1 ]]; then
    continue
  fi
  for mode in lazy eager; do
    stage="candidate-$mode"
    binary="$(compile_one "$stage" "$name" "$ADAMAS_BIN")"
    run_binary "$stage" "$name" "$binary" "$expected"
  done
done

if [[ "$ORIGINAL_ONLY" == 1 ]]; then
  printf 'PASS: original Crystal qualified force-depth return dependency cases (%s)\n' \
    "${SELECTED_CASES[*]}"
else
  printf 'PASS: force-depth return dependencies match original Crystal (%s)\n' \
    "${SELECTED_CASES[*]}"
fi
