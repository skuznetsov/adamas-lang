#!/usr/bin/env bash
# Deferred included-module snapshots must take authority over same-named owner
# parameters, while methods declared on the owner retain the owner's bindings.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deferred_included_module_binding.XXXXXX")"
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

SRC="$WORK_DIR/deferred_included_module_binding.cr"
BIN="$WORK_DIR/deferred_included_module_binding"
cat >"$SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Cmp(T)
  def binding_code : Int32
    T.code
  end

  def probe(other : T) : Int32
    which(other)
  end
end

struct UInt64
  def self.code : Int32
    20
  end
end

struct Int64
  def self.code : Int32
    40
  end
end

struct OwnerT(T)
  include Cmp(self)

  def self.code : Int32
    30
  end

  def owner_code : Int32
    T.code
  end

  def which(value : UInt64) : Int32
    2
  end

  def which(value : OwnerT(UInt64)) : Int32
    3
  end
end

struct OwnerU(U)
  include Cmp(self)

  def self.code : Int32
    30
  end

  def which(value : UInt64) : Int32
    2
  end

  def which(value : OwnerU(UInt64)) : Int32
    3
  end
end

struct ExplicitGenericSelf(T)
  include Cmp(ExplicitGenericSelf(T))

  def self.code : Int32
    30
  end
end

struct ExplicitUInt64(T)
  include Cmp(UInt64)

  def owner_code : Int32
    T.code
  end
end

owner_t = OwnerT(UInt64).new
owner_u = OwnerU(UInt64).new
explicit_self = ExplicitGenericSelf(UInt64).new
explicit_module = ExplicitUInt64(Int64).new

status = 0
status |= 1 unless owner_t.binding_code == 30
status |= 2 unless owner_t.probe(owner_t) == 3
status |= 4 unless owner_t.owner_code == 20
status |= 8 unless owner_u.binding_code == 30
status |= 16 unless owner_u.probe(owner_u) == 3
status |= 32 unless explicit_self.binding_code == 30
status |= 64 unless explicit_module.binding_code == 20
status |= 128 unless explicit_module.owner_code == 40
LibC.exit(status)
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
  echo "FAIL: deferred included-module bindings produced a nonzero status" >&2
  exit 1
fi

echo "PASS: deferred included-module and owner parameter bindings are distinct"
