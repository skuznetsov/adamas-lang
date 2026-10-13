#!/usr/bin/env bash
# `extend M` / `extend Meths(self)` inside a module must make M's instance defs
# callable as module class methods, with `D` bound to the extending module
# (`D::CarrierUInt`, `D::SHIFT`), also when nested inside another module.
# Mirrors Float::Printer::Dragonbox ImplInfo_* modules.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module_extend_generic_scope_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

status=0
check() {
  local case_name="$1" expected="$2"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
      "$WORK_DIR/$case_name.cr" --no-prelude -o "$WORK_DIR/$case_name" >"$WORK_DIR/$case_name.build.log" 2>&1; then
    echo "FAIL[$case_name]: compile failed" >&2
    tail -20 "$WORK_DIR/$case_name.build.log" >&2
    status=1
    return
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$case_name" 5 512 >"$WORK_DIR/$case_name.run.log" 2>&1 || true
  printf '%s\n' "$expected" >"$WORK_DIR/$case_name.expected"
  sed -n '/^=== STDOUT ===$/,/^===/p' "$WORK_DIR/$case_name.run.log" | grep -v '^===' | grep -v '^\[' >"$WORK_DIR/$case_name.actual" || true
  if ! diff -u "$WORK_DIR/$case_name.expected" "$WORK_DIR/$case_name.actual" >&2; then
    echo "FAIL[$case_name]" >&2
    status=1
  fi
}

cat >"$WORK_DIR/c1.cr" <<'CR'
lib LibC
  fun printf(fmt : UInt8*, ...) : Int32
end
module Meths
  def bits(u : UInt64)
    (u >> 4).to_i32!
  end
end
module Info64
  extend Meths
end
LibC.printf("%d\n", Info64.bits(256_u64))
CR
check c1 '16'

cat >"$WORK_DIR/c2.cr" <<'CR'
lib LibC
  fun printf(fmt : UInt8*, ...) : Int32
end
module Box
  module Meths(D)
    def bits(u : D::CarrierUInt)
      (u >> D::SHIFT).to_i32!
    end
  end
  module Info64
    extend Meths(self)
    SHIFT = 4
    alias CarrierUInt = UInt64
  end
end
LibC.printf("%d\n", Box::Info64.bits(256_u64))
CR
check c2 '16'

cat >"$WORK_DIR/c3.cr" <<'CR'
abstract struct Outer
end
lib LibC
  fun printf(fmt : UInt8*, ...) : Int32
end
module Outer::Box
  private module Meths(D)
    def bits(u : D::CarrierUInt)
      (u >> D::SHIFT).to_i32!
    end
  end
  private module ImplInfo_Float64
    extend Meths(self)
    SHIFT = 4
    alias CarrierUInt = UInt64
  end
  private module Impl(F, ImplInfo)
    def self.go(x)
      ImplInfo.bits(x) + 1
    end
  end
  {% for f, uint in {Float64 => UInt64} %}
    def self.run(x : {{ uint }})
      Impl({{ f }}, ImplInfo_{{ f }}).go(x)
    end
  {% end %}
end
LibC.printf("%d\n", Outer::Box.run(256_u64))
CR
check c3 '17'

if [ "$status" -ne 0 ]; then
  echo "FAIL: extend-in-module class method missing or D unbound" >&2
  exit 1
fi
echo "PASS: extend-in-module class methods resolve with D bound"
