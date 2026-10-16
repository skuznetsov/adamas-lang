#!/usr/bin/env bash
# Preserve Crystal's restriction specificity and declaration order between
# initialize-based allocators and explicit class-level new overloads.
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${COMPILER:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
elif [[ -d "$ROOT_DIR/../crystal/src" ]]; then
  CRYSTAL_STDLIB="$ROOT_DIR/../crystal/src"
else
  CRYSTAL_STDLIB=""
fi

if [[ ! -x "$SAFE_RUNNER" || ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL_BIN" ]]; then
  echo "ERROR: set COMPILER and ORIGINAL_CRYSTAL_BIN to executable paths" >&2
  exit 2
fi
if [[ -z "$CRYSTAL_STDLIB" || ! -d "$CRYSTAL_STDLIB" ]]; then
  echo "ERROR: set CRYSTAL_PATH to the original Crystal stdlib source directory" >&2
  exit 2
fi

if [[ -n "${LLVM_ROOT:-}" ]]; then
  PATH="$LLVM_ROOT/bin:$PATH"
  CRYSTAL_LIBRARY_PATH="$LLVM_ROOT/lib${CRYSTAL_LIBRARY_PATH:+:$CRYSTAL_LIBRARY_PATH}"
  export PATH CRYSTAL_LIBRARY_PATH
fi
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
export ADAMAS_LLVM_CACHE="${ADAMAS_LLVM_CACHE:-0}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/initializer-new-source-order.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/same_arena.cr" <<'CRYSTAL'
class BroadIntInitializerFirst
  alias Input = Nil | Bool | Int64 | String

  def initialize(@raw : Input)
    puts "broad-int-initialize"
  end

  def self.new(raw : Int) : self
    puts "broad-int-wrapper"
    allocate
  end
end

class BroadNumberInitializerFirst
  alias Input = Nil | Bool | Int64 | String

  def initialize(@raw : Input)
    puts "broad-number-initialize"
  end

  def self.new(raw : Number) : self
    puts "broad-number-wrapper"
    allocate
  end
end

class ExactInt64Wrapper
  alias Input = Nil | Bool | Int64 | String

  def initialize(@raw : Input)
    puts "exact-int64-initialize"
  end

  def self.new(raw : Int64) : self
    puts "exact-int64-wrapper"
    allocate
  end
end

class BroadIntWrapperFirst
  alias Input = Nil | Bool | Int64 | String

  def self.new(raw : Int) : self
    puts "reversed-int-wrapper"
    allocate
  end

  def initialize(@raw : Input)
    puts "reversed-int-initialize"
  end
end

alias ConstructorInputAlias = Int32

class SameScoreAliasAllocatorFirst
  alias Input = ConstructorInputAlias

  def initialize(@raw : Input)
    puts "alias-allocator-first"
  end

  def self.new(raw : ConstructorInputAlias) : self
    puts "alias-wrapper-second"
    allocate
  end
end

class SameScoreAliasWrapperFirst
  alias Input = ConstructorInputAlias

  def self.new(raw : ConstructorInputAlias) : self
    puts "alias-wrapper-first"
    allocate
  end

  def initialize(@raw : Input)
    puts "alias-allocator-second"
  end
end

BroadIntInitializerFirst.new(17_i64)
BroadNumberInitializerFirst.new(18_i64)
ExactInt64Wrapper.new(19_i64)
BroadIntWrapperFirst.new(20_i64)
SameScoreAliasAllocatorFirst.new(21_i32)
SameScoreAliasWrapperFirst.new(22_i32)
CRYSTAL

cat >"$WORK_DIR/cross_arena_initializer.cr" <<'CRYSTAL'
class CrossArenaConstructor
  alias Input = Nil | Bool | Int64 | String

  def initialize(@raw : Input)
    puts "cross-arena-initialize"
  end
end
CRYSTAL
cat >"$WORK_DIR/cross_arena_explicit_new.cr" <<'CRYSTAL'
class CrossArenaConstructor
  def self.new(raw : Int64) : self
    puts "cross-arena-exact-wrapper"
    allocate
  end
end
CRYSTAL
cat >"$WORK_DIR/cross_arena_main.cr" <<'CRYSTAL'
require "./cross_arena_initializer"
require "./cross_arena_explicit_new"
CrossArenaConstructor.new(23_i64)
CRYSTAL

cat >"$WORK_DIR/same_arena.expected" <<'OUTPUT'
broad-int-initialize
broad-number-initialize
exact-int64-wrapper
reversed-int-wrapper
alias-wrapper-second
alias-allocator-second
OUTPUT
cat >"$WORK_DIR/cross_arena.expected" <<'OUTPUT'
cross-arena-exact-wrapper
OUTPUT

run_build() {
  local producer="$1" compiler="$2" source="$3" output="$4" log="$5" status=0
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache.$output" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$source" -o "$output" \
      --no-debug --link-flags=-fuse-ld=/usr/bin/ld >"$log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache.$output" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$source" \
      --no-ast-cache --no-llvm-cache -o "$output" >"$log" 2>&1 || status=$?
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$producer]: compile exited $status for $(basename "$source")" >&2
    tail -30 "$log" >&2
    return 1
  fi
}

run_one() {
  local producer="$1" compiler="$2" name="$3" source="$4" expected="$5"
  local output="$WORK_DIR/$producer.$name" log="$WORK_DIR/$producer.$name.build.log"
  if ! run_build "$producer" "$compiler" "$source" "$output" "$log"; then
    return 1
  fi
  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.$name.run.resources.json" \
      "$SAFE_RUNNER" "$output" 10 512 >"$WORK_DIR/$producer.$name.run.log" 2>&1; then
    echo "FAIL[$producer]: runtime failed for $name" >&2
    cat "$WORK_DIR/$producer.$name.run.log" >&2
    return 1
  fi
  sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/{/^=== STDOUT ===$/d;/^=== STDERR ===$/d;p;}' \
    "$WORK_DIR/$producer.$name.run.log" >"$WORK_DIR/$producer.$name.actual"
  if ! diff -u "$expected" "$WORK_DIR/$producer.$name.actual" >&2; then
    echo "FAIL[$producer]: unexpected constructor source selection for $name" >&2
    return 1
  fi
  echo "PASS[$producer/$name]"
}

FAILURES=0
for producer in original candidate; do
  compiler="$COMPILER"
  if [[ "$producer" == original ]]; then
    compiler="$ORIGINAL_CRYSTAL_BIN"
  fi
  run_one "$producer" "$compiler" same-arena "$WORK_DIR/same_arena.cr" "$WORK_DIR/same_arena.expected" || FAILURES=$((FAILURES + 1))
  run_one "$producer" "$compiler" cross-arena "$WORK_DIR/cross_arena_main.cr" "$WORK_DIR/cross_arena.expected" || FAILURES=$((FAILURES + 1))
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "FAIL: $FAILURES constructor source-selection checks differed from Crystal" >&2
  exit 1
fi
echo "PASS: constructor selection matches Crystal for broad restrictions, explicit-new priority, declaration order, and separate arenas"
