#!/usr/bin/env bash
# Preserve canonical generic bindings in nominal registration and composite
# annotations while keeping unbound source names in their declaration scope.
# Compare both native outputs against an upstream Crystal oracle.
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${COMPILER:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-}"

if [[ ! -x "$SAFE_RUN" || ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL_BIN" ]]; then
  echo "ERROR: set ROOT_DIR, COMPILER, and ORIGINAL_CRYSTAL_BIN to executable paths" >&2
  exit 2
fi
if [[ -n "$CRYSTAL_STDLIB" && ! -d "$CRYSTAL_STDLIB" ]]; then
  echo "ERROR: CRYSTAL_PATH is not a directory: $CRYSTAL_STDLIB" >&2
  exit 2
fi

if [[ -n "${LLVM_ROOT:-}" ]]; then
  PATH="$LLVM_ROOT/bin:$PATH"
  CRYSTAL_LIBRARY_PATH="$LLVM_ROOT/lib${CRYSTAL_LIBRARY_PATH:+:$CRYSTAL_LIBRARY_PATH}"
  export PATH CRYSTAL_LIBRARY_PATH
fi
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
export ADAMAS_LLVM_CACHE="${ADAMAS_LLVM_CACHE:-0}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bound-annotation-identity.XXXXXX")"
FAILURES=0
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "$FAILURES" -ne 0 || "${KEEP_ARTIFACTS:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/direct.cr" <<'CRYSTAL'
module RegistrationIdentityScope
  class Payload
    getter marker : String
    def initialize(@marker : String)
    end
  end
  struct Box(T)
    getter value : T
    def initialize(@value : T)
    end
  end
end

class Payload
  getter marker : Int32
  def initialize(@marker : Int32)
  end
end

def identity(value : Payload)
  "global"
end

def identity(value : RegistrationIdentityScope::Payload)
  "local"
end

outer = RegistrationIdentityScope::Box(Payload).new(Payload.new(23))
puts identity(outer.value)
puts outer.value.marker
local = RegistrationIdentityScope::Box(RegistrationIdentityScope::Payload).new(RegistrationIdentityScope::Payload.new("shadow"))
puts identity(local.value)
puts local.value.marker
nested = RegistrationIdentityScope::Box(RegistrationIdentityScope::Box(Payload)).new(outer)
puts identity(nested.value.value)
puts nested.value.value.marker
CRYSTAL

cat >"$WORK_DIR/direct.expected" <<'EXPECTED'
global
23
local
shadow
global
23
EXPECTED

cat >"$WORK_DIR/composite.cr" <<'CRYSTAL'
module BoundAnnotationScope
  class Payload
    def initialize(@marker : String); end
  end
  struct Box(T)
    getter value : T
    def initialize(@value : T); end
  end
  struct ArrayBox(T)
    getter value : Array(T)
    def initialize(@value : Array(T)); end
  end
  struct NestedBox(T)
    getter value : Box(T)
    def initialize(@value : Box(T)); end
  end
  struct TupleBox(T)
    getter value : Tuple(T)
    def initialize(@value : Tuple(T)); end
  end
  struct MaybeBox(T)
    getter value : T?
    def initialize(@value : T?); end
  end
  struct MixedBox(T)
    getter bound : T
    getter local : Payload
    def initialize(@bound : T, @local : Payload); end
  end
end
class Payload
  def initialize(@marker : Int32); end
end
def identity(value : Payload); "global"; end
def identity(value : BoundAnnotationScope::Payload); "local"; end
payload = Payload.new(23)
local = BoundAnnotationScope::Payload.new("shadow")
puts identity(BoundAnnotationScope::ArrayBox(Payload).new([payload]).value[0])
puts identity(BoundAnnotationScope::NestedBox(Payload).new(BoundAnnotationScope::Box(Payload).new(payload)).value.value)
puts identity(BoundAnnotationScope::TupleBox(Payload).new({payload}).value[0])
if value = BoundAnnotationScope::MaybeBox(Payload).new(payload).value
  puts identity(value)
end
mixed = BoundAnnotationScope::MixedBox(Payload).new(payload, local)
puts identity(mixed.bound)
puts identity(mixed.local)
CRYSTAL

cat >"$WORK_DIR/composite.expected" <<'EXPECTED'
global
global
global
global
global
local
EXPECTED

cat >"$WORK_DIR/additional.cr" <<'CRYSTAL'
module BoundShapeScope
  class Payload
    def initialize(@marker : String); end
  end
  struct PointerBox(T)
    getter value : T*
    def initialize(@value : T*); end
  end
  struct NamedBox(T)
    getter value : NamedTuple(item: T)
    def initialize(@value : NamedTuple(item: T)); end
  end
  struct StaticBox(T)
    getter value : StaticArray(T, 1)
    def initialize(@value : StaticArray(T, 1)); end
  end
  struct NullableArrayBox(T)
    getter value : Array(T?)
    def initialize(@value : Array(T?)); end
  end
  struct MixedBox(T)
    getter value : NamedTuple(bound: T, local: Payload)
    def initialize(@value : NamedTuple(bound: T, local: Payload)); end
  end
end
class Payload
  def initialize(@marker : Int32); end
end
def identity(value : Payload); "global"; end
def identity(value : BoundShapeScope::Payload); "local"; end
payload = Payload.new(23)
local = BoundShapeScope::Payload.new("shadow")
puts identity(BoundShapeScope::PointerBox(Payload).new(pointerof(payload)).value.value)
puts identity(BoundShapeScope::NamedBox(Payload).new({item: payload}).value[:item])
puts identity(BoundShapeScope::StaticBox(Payload).new(StaticArray[payload]).value[0])
if value = BoundShapeScope::NullableArrayBox(Payload).new([payload] of Payload?).value[0]
  puts identity(value)
end
mixed = BoundShapeScope::MixedBox(Payload).new({bound: payload, local: local})
puts identity(mixed.value[:bound])
puts identity(mixed.value[:local])
CRYSTAL

cat >"$WORK_DIR/additional.expected" <<'EXPECTED'
global
global
global
global
global
local
EXPECTED

cat >"$WORK_DIR/forward.cr" <<'CRYSTAL'
class ForwardPayload
end
module ForwardAnnotationScope
  struct Box
    getter value : ForwardPayload?
    def initialize(@value : ForwardPayload? = nil); end
  end
  class ForwardPayload
  end
end
def identity(value : ::ForwardPayload); "global"; end
def identity(value : ForwardAnnotationScope::ForwardPayload); "local"; end
puts ForwardAnnotationScope::Box.new.value.nil?
if value = ForwardAnnotationScope::Box.new(ForwardAnnotationScope::ForwardPayload.new).value
  puts identity(value)
end
CRYSTAL

cat >"$WORK_DIR/forward.expected" <<'EXPECTED'
true
local
EXPECTED

cat >"$WORK_DIR/enum.cr" <<'CRYSTAL'
enum BoundFlag
  First
end
module BoundEnumScope
  enum BoundFlag
    First
  end
  struct MaybeBox(T)
    getter value : T?
    def initialize(@value : T?); end
  end
end
def identity(value : BoundFlag); "global-enum"; end
def identity(value : BoundEnumScope::BoundFlag); "local-enum"; end
if value = BoundEnumScope::MaybeBox(BoundFlag).new(BoundFlag::First).value
  puts identity(value)
end
if value = BoundEnumScope::MaybeBox(BoundEnumScope::BoundFlag).new(BoundEnumScope::BoundFlag::First).value
  puts identity(value)
end
CRYSTAL

cat >"$WORK_DIR/enum.expected" <<'EXPECTED'
global-enum
local-enum
EXPECTED

compile_case() {
  local stage="$1" name="$2" source="$3"
  local cache="$WORK_DIR/cache_${stage}_${name}"
  local log="$WORK_DIR/${stage}_${name}.build.log"
  local binary="$WORK_DIR/${stage}_${name}.bin"
  local status=0
  mkdir -p "$cache"

  if [[ "$stage" == "original" ]]; then
    if [[ -n "$CRYSTAL_STDLIB" ]]; then
      CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${stage}_${name}.build.resources" \
        "$SAFE_RUN" "$ORIGINAL_CRYSTAL_BIN" 240 8192 build "$source" \
        --no-debug --error-trace -o "$binary" \
        --link-flags=-fuse-ld=/usr/bin/ld >"$log" 2>&1 || status=$?
    else
      CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${stage}_${name}.build.resources" \
        "$SAFE_RUN" "$ORIGINAL_CRYSTAL_BIN" 240 8192 build "$source" \
        --no-debug --error-trace -o "$binary" \
        --link-flags=-fuse-ld=/usr/bin/ld >"$log" 2>&1 || status=$?
    fi
  else
    if [[ -n "$CRYSTAL_STDLIB" ]]; then
      CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${stage}_${name}.build.resources" \
        "$SAFE_RUN" "$COMPILER" 240 8192 "$source" \
        --no-ast-cache --no-llvm-cache --no-debug -o "$binary" \
        >"$log" 2>&1 || status=$?
    else
      CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${stage}_${name}.build.resources" \
        "$SAFE_RUN" "$COMPILER" 240 8192 "$source" \
        --no-ast-cache --no-llvm-cache --no-debug -o "$binary" \
        >"$log" 2>&1 || status=$?
    fi
  fi

  # Crystal and Adamas caches are disposable for each isolated compile.
  python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$cache"
  BUILD_STATUS="$status"
  BUILD_LOG="$log"
  BUILD_BINARY="$binary"
}

run_case() {
  local stage="$1" name="$2" binary="$3"
  local output="$WORK_DIR/${stage}_${name}.stdout"
  local log="$WORK_DIR/${stage}_${name}.run.log"
  local status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${stage}_${name}.run.resources" \
    "$SAFE_RUN" "$binary" 20 1024 >"$output" 2>"$log" || status=$?
  RUN_STATUS="$status"
  RUN_OUTPUT="$output"
  RUN_LOG="$log"
}

positive_case() {
  local name="$1" expected="$2" stage
  for stage in original candidate; do
    compile_case "$stage" "$name" "$WORK_DIR/$name.cr"
    if [[ "$BUILD_STATUS" -ne 0 ]]; then
      printf 'FAIL[%s/%s]: compilation failed\n' "$stage" "$name" >&2
      tail -20 "$BUILD_LOG" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
    run_case "$stage" "$name" "$BUILD_BINARY"
    if [[ "$RUN_STATUS" -ne 0 ]] || ! diff -u "$expected" "$RUN_OUTPUT" >&2; then
      printf 'FAIL[%s/%s]: runtime output differed from the expected result\n' "$stage" "$name" >&2
      tail -20 "$RUN_LOG" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
    printf 'PASS[%s/%s]\n' "$stage" "$name"
  done
  if [[ -f "$WORK_DIR/original_${name}.stdout" &&
        -f "$WORK_DIR/candidate_${name}.stdout" ]] &&
      ! diff -u "$WORK_DIR/original_${name}.stdout" \
        "$WORK_DIR/candidate_${name}.stdout" >&2; then
    printf 'FAIL[%s]: original and candidate outputs differ\n' "$name" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

positive_case direct "$WORK_DIR/direct.expected"
positive_case composite "$WORK_DIR/composite.expected"
positive_case additional "$WORK_DIR/additional.expected"
positive_case forward "$WORK_DIR/forward.expected"
positive_case enum "$WORK_DIR/enum.expected"

if [[ "$FAILURES" -ne 0 ]]; then
  printf 'FAILED: %d bound annotation identity check(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'PASS: canonical generic owner and bound annotation identities match Crystal across direct, composite, pointer, NamedTuple, StaticArray, nullable, enum and lexical controls\n'
