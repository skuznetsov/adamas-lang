#!/usr/bin/env bash
# Absolute receiver paths must stay rooted after `::` is stripped for HIR type
# lookup. Same-named declarations and aliases in the caller's namespace must
# not replace root classes, modules, or enums.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
# Oracle-only qualification: ORIGINAL_ONLY=1 CRYSTAL_BIN=path/to/crystal $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
KEEP_ARTIFACTS="${KEEP_ARTIFACTS:-0}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/absolute-root-receiver.XXXXXX")"

cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 || "$KEEP_ARTIFACTS" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ "$ORIGINAL_ONLY" != "0" && "$ORIGINAL_ONLY" != "1" ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" ]]; then
  echo "ERROR: safe runner is unavailable" >&2
  exit 2
fi
if [[ -n "$CRYSTAL_BIN" && ! -x "$CRYSTAL_BIN" ]]; then
  echo "ERROR: original Crystal compiler is not executable: $CRYSTAL_BIN" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" == "1" && -z "$CRYSTAL_BIN" ]]; then
  echo "ERROR: ORIGINAL_ONLY=1 requires CRYSTAL_BIN or ORIGINAL_CRYSTAL_BIN" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != "1" && ! -x "$ADAMAS_BIN" ]]; then
  echo "ERROR: Adamas compiler is not executable: $ADAMAS_BIN" >&2
  exit 2
fi

write_header() {
  cat > "$1" <<'CR'
lib LibC
  fun putchar(value : Int32) : Int32
end

class AbsoluteReceiverClass
  def self.marker
    LibC.putchar(65_i32)
  end
end
alias AbsoluteReceiverClassAlias = AbsoluteReceiverClass

module AbsoluteReceiverModule
  def self.marker
    LibC.putchar(77_i32)
  end
end
alias AbsoluteReceiverModuleAlias = AbsoluteReceiverModule

enum AbsoluteReceiverEnum
  First

  def self.marker
    LibC.putchar(69_i32)
  end
end
alias AbsoluteReceiverEnumAlias = AbsoluteReceiverEnum

class AbsoluteReceiverRootItem
  def marker : Int32
    LibC.putchar(73_i32)
  end
end

class AbsoluteReceiverRootBox(T)
  def initialize(@value : T)
  end

  def each(&block : T ->)
    yield @value
  end

  def self.marker
    T.new.marker
  end
end

class AbsoluteReceiverRootParent(T)
  def self.marker
    T.new.marker
  end
end

# This family is first instantiated inside the shadowing namespace below.
class AbsoluteReceiverColdBox(T)
  def initialize(@value : T)
  end

  def each(&block : T ->)
    yield @value
  end

  def self.marker
    T.new.marker
  end
end

module AbsoluteReceiverAliasTarget
  class Inner
    def self.marker
      LibC.putchar(82_i32)
    end
  end
end
alias AbsoluteReceiverQualifiedAlias = AbsoluteReceiverAliasTarget

module RootQualifiedAliasNamespace
  module Target
    class Inner
      def self.marker
        LibC.putchar(84_i32)
      end
    end
  end
  alias NestedAlias = Target
end

module AbsoluteReceiverShadow
  class AbsoluteReceiverRootItem
    def marker : Int32
      LibC.putchar(105_i32)
    end
  end

  class AbsoluteReceiverColdBox(T)
    def initialize(@value : T)
    end

    def each(&block : T ->)
      LibC.putchar(120_i32)
      yield @value
    end

    def self.marker
      LibC.putchar(120_i32)
    end
  end

  class AbsoluteReceiverClass
    def self.marker
      LibC.putchar(97_i32)
    end
  end

  alias AbsoluteReceiverClassAlias = AbsoluteReceiverClass

  module AbsoluteReceiverModule
    def self.marker
      LibC.putchar(109_i32)
    end
  end

  alias AbsoluteReceiverModuleAlias = AbsoluteReceiverModule

  enum AbsoluteReceiverEnum
    First

    def self.marker
      LibC.putchar(101_i32)
    end
  end

  alias AbsoluteReceiverEnumAlias = AbsoluteReceiverEnum

  module AbsoluteReceiverQualifiedAlias
    class Inner
      def self.marker
        LibC.putchar(120_i32)
      end
    end
  end

  module RootQualifiedAliasNamespace
    module NestedAlias
      class Inner
        def self.marker
          LibC.putchar(120_i32)
        end
      end
    end
  end
CR
}

write_header "$WORK_DIR/header.cr"
cat "$WORK_DIR/header.cr" > "$WORK_DIR/absolute_root_receivers.cr"
cat >> "$WORK_DIR/absolute_root_receivers.cr" <<'CR'

  class AbsoluteReceiverRootParent(T)
    def self.marker
      LibC.putchar(120_i32)
    end
  end

  class FixedRootParent(T) < ::AbsoluteReceiverRootParent(::AbsoluteReceiverRootItem)
  end

  class ForwardedRootParent(T) < ::AbsoluteReceiverRootParent(T)
  end

  class Runner
    def self.run
      ::AbsoluteReceiverClass.marker
      ::AbsoluteReceiverClass.marker()
      ::AbsoluteReceiverClassAlias.marker
      ::AbsoluteReceiverClassAlias.marker()

      ::AbsoluteReceiverModule.marker
      ::AbsoluteReceiverModule.marker()
      ::AbsoluteReceiverModuleAlias.marker
      ::AbsoluteReceiverModuleAlias.marker()

      ::AbsoluteReceiverEnum.marker
      ::AbsoluteReceiverEnum.marker()
      ::AbsoluteReceiverEnumAlias.marker
      ::AbsoluteReceiverEnumAlias.marker()

      ::AbsoluteReceiverQualifiedAlias::Inner.marker
      ::AbsoluteReceiverQualifiedAlias::Inner.marker()

      ::RootQualifiedAliasNamespace::NestedAlias::Inner.marker
      ::RootQualifiedAliasNamespace::NestedAlias::Inner.marker()

      AbsoluteReceiverRootBox(::AbsoluteReceiverRootItem).new(::AbsoluteReceiverRootItem.new).each do |item|
        item.marker
      end
      AbsoluteReceiverRootBox(AbsoluteReceiverRootItem).new(AbsoluteReceiverRootItem.new).each do |item|
        item.marker
      end
      AbsoluteReceiverRootBox(Tuple(::AbsoluteReceiverRootItem, AbsoluteReceiverRootItem)).new(
        {::AbsoluteReceiverRootItem.new, AbsoluteReceiverRootItem.new}
      ).each do |items|
        items[0].marker
        items[1].marker
      end

      ::AbsoluteReceiverRootBox(::AbsoluteReceiverRootItem).marker
      ::AbsoluteReceiverRootBox(AbsoluteReceiverRootItem).marker

      ::AbsoluteReceiverColdBox(::AbsoluteReceiverRootItem).new(::AbsoluteReceiverRootItem.new).each do |item|
        item.marker
      end
      ::AbsoluteReceiverColdBox(AbsoluteReceiverRootItem).new(AbsoluteReceiverRootItem.new).each do |item|
        item.marker
      end
      ::AbsoluteReceiverColdBox(::AbsoluteReceiverRootItem).marker
      ::AbsoluteReceiverColdBox(AbsoluteReceiverRootItem).marker

      FixedRootParent(Int32).marker
      ForwardedRootParent(::AbsoluteReceiverRootItem).marker
      ForwardedRootParent(AbsoluteReceiverRootItem).marker

      LibC.putchar(10_i32)
    end
  end
end

AbsoluteReceiverRootBox(::AbsoluteReceiverRootItem).new(AbsoluteReceiverRootItem.new).each do |item|
  item.marker
end
AbsoluteReceiverRootBox(AbsoluteReceiverRootItem).new(AbsoluteReceiverRootItem.new).each do |item|
  item.marker
end
AbsoluteReceiverShadow::Runner.run
CR

write_negative() {
  local name="$1" declaration="$2" receiver="$3" call_suffix="${4:-}"
  cat "$WORK_DIR/header.cr" > "$WORK_DIR/$name.cr"
  cat >> "$WORK_DIR/$name.cr" <<CR

  $declaration

  def self.run
    ::$receiver.marker$call_suffix
  end
end

AbsoluteReceiverShadow.run
CR
}

# The root path is missing in each negative fixture, while a same-named local
# declaration exists. An absolute lookup must reject instead of finding it.
write_negative missing_root_class $'class MissingAbsoluteReceiverClass\n    def self.marker\n      LibC.putchar(88_i32)\n    end\n  end' 'MissingAbsoluteReceiverClass'
write_negative missing_root_module $'module MissingAbsoluteReceiverModule\n    def self.marker\n      LibC.putchar(88_i32)\n    end\n  end' 'MissingAbsoluteReceiverModule'
write_negative missing_root_enum $'enum MissingAbsoluteReceiverEnum\n    First\n\n    def self.marker\n      LibC.putchar(88_i32)\n    end\n  end' 'MissingAbsoluteReceiverEnum'
write_negative missing_root_class_parenthesized $'class MissingAbsoluteReceiverClass\n    def self.marker\n      LibC.putchar(88_i32)\n    end\n  end' 'MissingAbsoluteReceiverClass' '()'

POSITIVE=absolute_root_receivers
NEGATIVES=(missing_root_class missing_root_class_parenthesized missing_root_module missing_root_enum)
EXPECTED_OUTPUT='IIAAAAMMMMEEEERRTTIiIiIiIiIiIIi'

exit_code_of() {
  (grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9') || true
}

# Semantic negative cases must be ordinary compiler diagnostics. A timeout,
# resource kill, crash, or signal is not evidence that the source is rejected.
semantic_rejection() {
  local status="$1" log="$2"
  [[ "$status" == "1" ]] || return 1
  [[ "$(exit_code_of "$log")" == "1" ]] || return 1
  if grep -Eqi '\[(KILL|CRASH)\]|Segfault|Abort|out of memory|resource limit' "$log"; then
    return 1
  fi
  grep -Eqi 'undefined constant|unknown constant|undefined method|not a constant|can.t resolve' "$log"
}

run_binary_exact() {
  local name="$1" binary="$2" stdout="$3" log="$4" status=0
  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 256 \
      >"$stdout" 2>"$log"; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" != "0" || "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s: safe native run did not exit 0\n' "$name" >&2
    return 1
  fi
  if ! printf '%s\n' "$EXPECTED_OUTPUT" | cmp -s - "$stdout"; then
    printf 'FAIL %s: stdout differed from exact expected output\n' "$name" >&2
    return 1
  fi
}

# Qualify every fixture with original Crystal before running the candidate.
if [[ -n "$CRYSTAL_BIN" ]]; then
  original_log="$WORK_DIR/$POSITIVE.orig.build.log"
  if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$SAFE_RUNNER" "$CRYSTAL_BIN" 120 4096 \
      build --prelude=empty "$WORK_DIR/$POSITIVE.cr" -o "$WORK_DIR/$POSITIVE.orig" \
      >"$original_log" 2>&1; then
    original_build_status=0
  else
    original_build_status=$?
  fi
  if [[ "$original_build_status" != "0" || "$(exit_code_of "$original_log")" != "0" ]]; then
    printf 'ORACLE FAIL: original rejects %s\n' "$POSITIVE" >&2
    cat "$original_log" >&2
    exit 2
  fi
  if ! run_binary_exact "$POSITIVE original" "$WORK_DIR/$POSITIVE.orig" \
      "$WORK_DIR/$POSITIVE.orig.stdout" "$WORK_DIR/$POSITIVE.orig.run.log"; then
    exit 2
  fi

  for name in "${NEGATIVES[@]}"; do
    log="$WORK_DIR/$name.orig.build.log"
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$SAFE_RUNNER" "$CRYSTAL_BIN" 120 4096 \
        build --prelude=empty "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" \
        >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
    if ! semantic_rejection "$status" "$log"; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      cat "$log" >&2
      exit 2
    fi
  done
fi

if [[ "$ORIGINAL_ONLY" == "1" ]]; then
  printf 'PASS: original Crystal qualified root class/module/enum receiver paths and strict negatives\n'
  exit 0
fi

failures=0
for mode in lazy eager; do
  if [[ "$mode" == eager ]]; then
    export ADAMAS_EAGER_HIR=1
  else
    unset ADAMAS_EAGER_HIR
  fi
  log="$WORK_DIR/$POSITIVE.$mode.adamas.log"
  if "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$POSITIVE.cr" \
      -o "$WORK_DIR/$POSITIVE.$mode.adamas" >"$log" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" != 0 || "$(exit_code_of "$log")" != 0 ]]; then
    printf 'FAIL %s/%s (compile): %s\n' "$mode" "$POSITIVE" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
  elif run_binary_exact "$POSITIVE $mode candidate" "$WORK_DIR/$POSITIVE.$mode.adamas" \
      "$WORK_DIR/$POSITIVE.$mode.adamas.stdout" "$WORK_DIR/$POSITIVE.$mode.adamas.run.log"; then
    printf 'PASS %s/%s\n' "$mode" "$POSITIVE"
  else
    failures=$((failures + 1))
  fi

  for name in "${NEGATIVES[@]}"; do
    log="$WORK_DIR/$name.$mode.adamas.log"
    if "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
        -o "$WORK_DIR/$name.$mode.adamas" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
    if semantic_rejection "$status" "$log"; then
      printf 'PASS %s/%s (semantic rejection)\n' "$mode" "$name"
    else
      printf 'FAIL %s/%s (not a semantic rejection)\n' "$mode" "$name"
      cat "$log" >&2
      failures=$((failures + 1))
    fi
  done
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d absolute root receiver case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'absolute root receiver cases passed\n'
