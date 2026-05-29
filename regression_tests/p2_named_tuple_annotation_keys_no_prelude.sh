#!/usr/bin/env bash
# Guard namespaced NamedTuple(...) annotations against key erasure.
#
# The parser uses Array(NamedTuple(span: Span, condition: ExprId, body: ExprId))
# in macro-if branch stacks. If generic type materialization resolves the full
# `key: Type` entry as a type parameter, keys are erased and later
# branch[:condition] lowers to a runtime NamedTuple#[](Symbol) call/stub.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_named_tuple_keys_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
PREFIX="$TMP_DIR/out"
LOG="$TMP_DIR/emit.log"

cat >"$SRC" <<'CR'
class Object
end

class Reference < Object
end

class Array(T) < Reference
  def initialize
  end

  def <<(value : T)
  end

  def unsafe_fetch(index : Int32) : T
    uninitialized T
  end
end

module Adamas
  module Compiler
    module Frontend
      class Span
      end

      struct ExprId
        def initialize(@index : Int32)
        end
      end

      def self.probe
        branches = [] of NamedTuple(span: Span, condition: ExprId, body: ExprId)
        branches << {span: Span.new, condition: ExprId.new(1), body: ExprId.new(2)}
        branch = branches.unsafe_fetch(0)
        branch[:condition]
      end
    end
  end
end

Adamas::Compiler::Frontend.probe
CR

BOOTSTRAP_IR_TIMEOUT_SEC="${BOOTSTRAP_IR_TIMEOUT_SEC:-60}" \
BOOTSTRAP_IR_MEM_MB="${BOOTSTRAP_IR_MEM_MB:-2048}" \
  "$ROOT_DIR/scripts/emit_bootstrap_ir.sh" "$COMPILER" "$SRC" "$PREFIX" >"$LOG" 2>&1

if [[ ! -s "$PREFIX.hir" ]]; then
  echo "p2 named tuple annotation keys regression: missing HIR artifact" >&2
  cat "$LOG" >&2
  exit 1
fi

if grep -Eq 'NamedTuple\([A-Za-z0-9_:]+::Span, [A-Za-z0-9_:]+::ExprId, [A-Za-z0-9_:]+::ExprId\)#\[\]\$Symbol' "$PREFIX.hir"; then
  echo "p2 named tuple annotation keys regression: keyless NamedTuple#[](Symbol) call emitted" >&2
  grep -En 'NamedTuple\(.*Span.*ExprId.*ExprId.*\)#\[\]\$Symbol' "$PREFIX.hir" >&2 || true
  exit 1
fi

if grep -Eq 'type\.[0-9]+ = NamedTuple NamedTuple\([A-Za-z0-9_:]+::Span, [A-Za-z0-9_:]+::ExprId, [A-Za-z0-9_:]+::ExprId\)' "$PREFIX.hir"; then
  echo "p2 named tuple annotation keys regression: keyless NamedTuple type materialized" >&2
  grep -En 'NamedTuple NamedTuple\(.*Span.*ExprId.*ExprId.*\)' "$PREFIX.hir" >&2 || true
  exit 1
fi

if ! grep -q 'index_get .* : ' "$PREFIX.hir"; then
  echo "p2 named tuple annotation keys regression: branch[:condition] did not lower to index_get" >&2
  tail -80 "$PREFIX.hir" >&2
  exit 1
fi

echo "p2_named_tuple_annotation_keys_no_prelude_ok"
