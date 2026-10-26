#!/usr/bin/env bash
# A bare restriction that names an alias (`node : TypedNode` with
# `alias TypedNode = Node`) is a type, not a free variable. Return-type
# inference bound it like `forall T` to the argument's concrete type, so after
# `lit_s(IdNode.new)` the restriction meant IdNode and the later
# `lit(node)` from `lit_s(node : TypedNode)` with a Node argument failed:
# stage 2 stopped with "no overload matches
# Adamas::Compiler::Frontend.node_literal for argument types (...::Node)".
# A real `forall T` must still bind even when an unrelated `alias Q::T`
# exists, and an alias restriction must still reject a non-Node argument.
# Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/alias-restriction-free-var.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  {
    cat <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Ad
  module Q
    alias T = Int32
  end

  module Fr
    abstract class Node
      abstract def k : Int32
    end

    class IdNode < Node
      def k : Int32
        1
      end
    end

    class BoolNode < Node
      def k : Int32
        3
      end
    end

    class StrNode < Node
      def k : Int32
        2
      end
    end

    alias TypedNode = Node

    def self.lit(node : IdNode) : Int32?
      10
    end

    def self.lit(node : TypedNode) : Int32?
      nil
    end

    def self.lit_s(node : TypedNode) : Int32?
      if node.is_a?(BoolNode)
        return 5
      end

      lit(node)
    end

    def self.wide(x : T) : T forall T
      x
    end
  end

  class User
    def go(n : Fr::Node) : Int32
      if v = Fr.lit_s(n)
        v
      else
        40
      end
    end
  end
end

def sz(x : Int64) : Int32
  42
end

def sz(x : Int32) : Int32
  1
end
HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

write_case concrete_then_base_in_method "c = (Ad::Fr.lit_s(Ad::Fr::IdNode.new) || 0) &- 10
n = Ad::Fr::StrNode.new.as(Ad::Fr::Node)
LibC.exit(Ad::User.new.go(n) &+ 2 &+ c)"
write_case concrete_then_base_top_level "c = Ad::Fr.lit_s(Ad::Fr::IdNode.new) || 0
v = Ad::Fr.lit_s(Ad::Fr::StrNode.new.as(Ad::Fr::Node)) || 32
LibC.exit(v &+ c)"
write_case forall_shadowing_alias_binds "LibC.exit(sz(Ad::Fr.wide(5_i64)))"
# Negative: an Int32 is not a TypedNode.
write_case alias_restriction_rejects "LibC.exit(Ad::Fr.lit_s(7) || 1)"

POSITIVE=(concrete_then_base_in_method concrete_then_base_top_level forall_shadowing_alias_binds)
NEGATIVE=(alias_restriction_rejects)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
  for name in "${NEGATIVE[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${POSITIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected 42\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]] && grep -q "no overload matches" "$log"; then
    printf 'PASS %s (rejected)\n' "$name"
  else
    printf 'FAIL %s: expected an overload error\n' "$name"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d alias restriction case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Alias restriction cases passed\n'
