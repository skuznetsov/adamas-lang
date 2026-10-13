#!/usr/bin/env bash
# A method-level forall name shadows an identically named included-module
# parameter only for that method; neighboring module and owner bindings remain.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/included_method_same_param_forall.XXXXXX")"
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

SRC="$WORK_DIR/included_method_same_param_forall.cr"
BIN="$WORK_DIR/included_method_same_param_forall"
cat >"$SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct UInt64
  def self.binding_code : Int32
    20
  end
end

struct Int64
  def self.binding_code : Int32
    40
  end
end

struct Int32
  def self.binding_code : Int32
    11
  end
end

struct Float64
  def self.binding_code : Int32
    12
  end
end

module ForallShadowFlow(T)
  def echo(value : T) : T forall T
    value
  end

  def method_binding(value : T) : Int32 forall T
    T.binding_code
  end

  def module_binding : Int32
    T.binding_code
  end
end

class ForallShadowOwner(U)
  include ForallShadowFlow(UInt64)

  def owner_binding : Int32
    U.binding_code
  end
end

def tag(value : Int32) : Int32
  value == 42 ? 1 : 0
end

def tag(value : Float64) : Int32
  value == 3.5 ? 2 : 0
end

owner = ForallShadowOwner(Int64).new
ok = tag(owner.echo(42)) == 1 && tag(owner.echo(3.5)) == 2 &&
     owner.method_binding(42) == 11 && owner.method_binding(3.5) == 12 &&
     owner.module_binding == 20 && owner.owner_binding == 40
LibC.exit(ok ? 0 : 1)
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
  echo "FAIL: method forall and included-module bindings were conflated" >&2
  exit 1
fi

echo "PASS: method forall shadows only its same-named included-module binding"
