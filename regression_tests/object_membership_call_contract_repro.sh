#!/usr/bin/env bash
# Object#in? keeps the concrete receiver and collection argument at inherited
# wrapper callsites, including full-prelude Range and reference collections.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"

[[ -x "$SAFE_RUNNER" && -x "$ORIGINAL_CRYSTAL_BIN" ]] || {
  echo "ERROR: set ORIGINAL_CRYSTAL_BIN and keep scripts/run_safe.sh executable" >&2
  exit 2
}
if [[ "${ORIGINAL_ONLY:-0}" != "1" && ! -x "$COMPILER" ]]; then
  echo "ERROR: candidate compiler is not executable: $COMPILER" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/object-membership-call-contract.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR"/*.cache
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

safe_passthrough() {
  local label="$1"
  shift
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.resources" \
    "$SAFE_RUNNER" "$@" >"$WORK_DIR/$label.stdout" 2>"$WORK_DIR/$label.log"; then
    cat "$WORK_DIR/$label.log" >&2
    return 1
  fi
  grep -Eq '^\[EXIT: 0\] after ' "$WORK_DIR/$label.log" || {
    cat "$WORK_DIR/$label.log" >&2
    return 1
  }
}

# Resolve the active compiler and its stock stdlib rather than a pinned checkout.
safe_passthrough original-version "$ORIGINAL_CRYSTAL_BIN" 10 1024 --version
ORACLE_VERSION="$(sed -n '1p' "$WORK_DIR/original-version.stdout")"
[[ "$ORACLE_VERSION" == Crystal* ]] || exit 2
CRYSTAL_STDLIB="${CRYSTAL_PATH:-}"
if [[ -z "$CRYSTAL_STDLIB" ]]; then
  safe_passthrough original-stdlib "$ORIGINAL_CRYSTAL_BIN" 15 1024 env CRYSTAL_PATH
  CRYSTAL_STDLIB="$(sed -e 's/\r$//' "$WORK_DIR/original-stdlib.stdout")"
fi
[[ -d "$CRYSTAL_STDLIB" ]] || {
  echo "ERROR: stock Crystal stdlib directory not found: $CRYSTAL_STDLIB" >&2
  exit 2
}

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

class AlphaNeedle
  getter code : Int32

  def initialize(@code : Int32)
  end
end

class BetaNeedle
  getter code : Int32

  def initialize(@code : Int32)
  end
end

class ReferenceCollection
  def initialize(@alpha_code : Int32, @beta_code : Int32)
  end

  def includes?(value : AlphaNeedle) : Bool
    matches?(value)
  end

  def includes?(value : BetaNeedle) : Bool
    matches?(value)
  end

  private def matches?(value : AlphaNeedle) : Bool
    value.code == @alpha_code
  end

  private def matches?(value : BetaNeedle) : Bool
    value.code == @beta_code
  end
end

class OverrideCollection
  def accepts?(code : Int32) : Bool
    code == 41
  end
end

class OverrideSubject
  def initialize(@code : Int32)
  end

  # Keep this one ordinary collection argument distinct from the Object wrapper.
  def in?(collection : OverrideCollection) : Bool
    collection.accepts?(@code)
  end
end

# This unrelated, reachable overload must not be swept into a broad
# Object#includes?(Object) virtual target while lowering the wrappers above.
class StringOnlyCollection
  def includes?(value : String) : Bool
    value == "membership-probe"
  end
end

C.exit(1) unless 'b'.in?('a'..'c')
C.exit(2) if 'c'.in?('a'...'c')
C.exit(3) unless 3_i32.in?(1_i32..4_i32)
C.exit(4) if 4_i32.in?(1_i32...4_i32)
C.putchar(82)

collection = ReferenceCollection.new(101, 202)
alpha = AlphaNeedle.new(101)
beta = BetaNeedle.new(202)
C.exit(5) unless alpha.in?(collection)
C.exit(6) if AlphaNeedle.new(999).in?(collection)
C.putchar(65)
C.exit(7) unless beta.in?(collection)
C.exit(8) if BetaNeedle.new(999).in?(collection)
C.putchar(66)

override_collection = OverrideCollection.new
C.exit(9) unless OverrideSubject.new(41).in?(override_collection)
C.exit(10) if OverrideSubject.new(42).in?(override_collection)
C.putchar(79)

string_collection = StringOnlyCollection.new
C.exit(11) unless string_collection.includes?("membership-probe")
C.exit(12) if string_collection.includes?("other")
C.putchar(85)
C.putchar(10)
CRYSTAL
printf 'RABOU\n' >"$WORK_DIR/positive.expected"
: >"$WORK_DIR/runtime.stderr.expected"

cat >"$WORK_DIR/wrong_type.cr" <<'CRYSTAL'
class StringOnlyCollection
  def includes?(value : String) : Bool
    value == "membership-probe"
  end
end

'a'.in?(StringOnlyCollection.new)
CRYSTAL

GC_LINK_FLAGS="${GC_LINK_FLAGS:--lgc}"
if [[ -z "${GC_LIBRARY_DIR:-}" ]]; then
  for candidate in /opt/homebrew/opt/bdw-gc/lib /usr/local/opt/bdw-gc/lib; do
    if [[ -d "$candidate" ]]; then
      GC_LIBRARY_DIR="$candidate"
      break
    fi
  done
fi
if [[ -n "${GC_LIBRARY_DIR:-}" ]]; then
  GC_LINK_FLAGS="-L$GC_LIBRARY_DIR $GC_LINK_FLAGS"
fi

run_binary() {
  local label="$1" binary="$2" status=0
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.run.resources" \
    "$SAFE_RUNNER" "$binary" 15 512 >"$WORK_DIR/$label.stdout" \
    2>"$WORK_DIR/$label.run.log"; then
    cat "$WORK_DIR/$label.run.log" >&2
    return 1
  fi
  grep -Eq '^\[EXIT: 0\] after ' "$WORK_DIR/$label.run.log" || {
    cat "$WORK_DIR/$label.run.log" >&2
    return 1
  }
  awk '/^=== STDERR ===$/ { capture=1; next } /^\[EXIT: / { capture=0 } capture { print }' \
    "$WORK_DIR/$label.run.log" >"$WORK_DIR/$label.stderr"
  diff -u "$WORK_DIR/positive.expected" "$WORK_DIR/$label.stdout"
  diff -u "$WORK_DIR/runtime.stderr.expected" "$WORK_DIR/$label.stderr"
}

compile_and_run_positive() {
  local stage="$1" mode="$2" compiler="$3" status=0
  local label="$stage-$mode" cache="$WORK_DIR/$stage-$mode.cache"
  local binary="$WORK_DIR/$label.bin" log="$WORK_DIR/$label.compile.log"

  if [[ "$stage" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 240 8192 build "$WORK_DIR/positive.cr" \
      --no-debug --error-trace "--link-flags=$GC_LINK_FLAGS" -o "$binary" \
      >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    local eager=0
    [[ "$mode" != eager ]] || eager=1
    local candidate_link_flags="${ADAMAS_EXTRA_LINK_FLAGS:-} $GC_LINK_FLAGS"
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_EAGER_HIR="$eager" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="$candidate_link_flags" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 240 8192 "$WORK_DIR/positive.cr" \
      --no-ast-cache --no-llvm-cache -o "$binary" \
      >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$label]: compile exited $status" >&2
    tail -40 "$log" >&2
    return 1
  fi
  run_binary "$label" "$binary"
}

compile_and_expect_wrong_type_rejection() {
  local stage="$1" mode="$2" compiler="$3" status=0
  local label="$stage-$mode-wrong-type" cache="$WORK_DIR/$stage-$mode-wrong-type.cache"
  local log="$WORK_DIR/$label.compile.log"

  if [[ "$stage" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$WORK_DIR/wrong_type.cr" \
      --no-debug --error-trace "--link-flags=$GC_LINK_FLAGS" \
      -o "$WORK_DIR/$label.bin" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    local eager=0
    [[ "$mode" != eager ]] || eager=1
    local candidate_link_flags="${ADAMAS_EXTRA_LINK_FLAGS:-} $GC_LINK_FLAGS"
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_EAGER_HIR="$eager" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="$candidate_link_flags" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$label.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$WORK_DIR/wrong_type.cr" \
      --no-ast-cache --no-llvm-cache \
      -o "$WORK_DIR/$label.bin" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi

  if [[ "$status" -eq 0 ]]; then
    echo "FAIL[$label]: compiler accepted Char against String-only includes?" >&2
    return 1
  fi
  if ! grep -Eq '^\[EXIT: [1-9][0-9]*\] after ' "$log" || \
     grep -q '^\[KILL\]' "$log" || ! grep -Eqi 'includes\?' "$log"; then
    echo "FAIL[$label]: rejection did not identify the nested includes? contract" >&2
    tail -40 "$log" >&2
    return 1
  fi
}

# Establish original behavior before any candidate result is considered.
compile_and_run_positive original oracle "$ORIGINAL_CRYSTAL_BIN"
compile_and_expect_wrong_type_rejection original oracle "$ORIGINAL_CRYSTAL_BIN"
echo "ORACLE[object-membership]: $ORACLE_VERSION accepts positive cases and rejects wrong-typed includes?"

if [[ "${ORIGINAL_ONLY:-0}" == "1" ]]; then
  echo "PASS[object-membership-oracle-only]: original behavior qualified"
  exit 0
fi

for mode in lazy eager; do
  compile_and_run_positive candidate "$mode" "$COMPILER"
  compile_and_expect_wrong_type_rejection candidate "$mode" "$COMPILER"
  echo "PASS[object-membership/$mode]: output, exit status, and wrong-type rejection match Crystal"
done

echo "PASS[object-membership-call-contract]: full-prelude ranges, reference overloads, override, and strict rejection match $ORACLE_VERSION"
