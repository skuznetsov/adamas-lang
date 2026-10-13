#!/usr/bin/env bash
# Included method-forall actuals retain nominal identity through return types
# and method bodies without changing lexical resolution of source annotations.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/included_forall_actual_type_namespace.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

SRC="$WORK_DIR/included_forall_actual_type_namespace.cr"
BIN="$WORK_DIR/included_forall_actual_type_namespace"
cat >"$SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun printf(format : UInt8*, ...) : Int32
end

class Token
  def self.marker : Int32
    1
  end

  def marker : Int32
    1
  end
end

struct UInt64
  def self.marker : Int32
    20
  end
end

struct Int64
  def self.marker : Int32
    40
  end
end

alias RootToken = ::Token

module Scope
  class Token
    def self.marker : Int32
      2
    end

    def marker : Int32
      2
    end
  end

  module ForallIdentityFlow(U)
    def identity(value : T) : T forall T
      value
    end

    def identity_marker(value : T) : Int32 forall T
      T.marker
    end

    def identity_marker_call(value : T) : Int32 forall T
      T.marker()
    end

    def pair_with_actual_first(value : T) : Tuple(T, Token) forall T
      {value, Token.new}
    end

    def pair_with_actual_last(value : T) : Tuple(::Token, T) forall T
      {::Token.new, value}
    end

    def module_binding : Int32
      U.marker
    end
  end
end

class ForallIdentityOwner(U)
  include Scope::ForallIdentityFlow(UInt64)

  def owner_binding : Int32
    U.marker
  end
end

def root_token_code(value : ::Token) : Int32
  value.marker
end

def scoped_token_code(value : Scope::Token) : Int32
  value.marker
end

def pair_code(value : Tuple(::Token, Scope::Token)) : Int32
  value[0].marker * 10 + value[1].marker
end

owner = ForallIdentityOwner(Int64).new
root_identity = owner.identity(::Token.new)
scoped_identity = owner.identity(Scope::Token.new)
root_first = owner.pair_with_actual_first(::Token.new)
scoped_last = owner.pair_with_actual_last(Scope::Token.new)

failures = 0
failures |= 1 unless root_token_code(root_identity) == 1
failures |= 2 unless scoped_token_code(scoped_identity) == 2
failures |= 4 unless owner.identity_marker(::Token.new) == 1
failures |= 8 unless owner.identity_marker(Scope::Token.new) == 2
failures |= 16 unless pair_code(root_first) == 12
failures |= 32 unless pair_code(scoped_last) == 12
failures |= 64 unless owner.module_binding == 20
failures |= 128 unless owner.owner_binding == 40
failures |= 256 unless owner.identity_marker_call(::Token.new) == 1
failures |= 512 unless owner.identity_marker_call(Scope::Token.new) == 2
LibC.printf("FAILURE_MASK=%d\n", failures)
LibC.exit(failures == 0 ? 0 : 1)
CR

if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/build.resources" \
  "$RUN_SAFE" "$COMPILER" 120 8192 "$SRC" --no-prelude -o "$BIN" \
  >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/run.resources" \
  "$RUN_SAFE" "$BIN" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  cat "$WORK_DIR/run.log" >&2
  echo "FAIL: included forall actual type identity or lexical tuple binding was lost" >&2
  exit 1
fi

echo "PASS: included forall returns and both static call forms preserve nominal identity"
