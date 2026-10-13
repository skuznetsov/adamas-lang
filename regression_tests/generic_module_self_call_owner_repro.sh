#!/usr/bin/env bash
# A bare class-method call (`helper(x)`) inside a specialized generic module
# (`Impl(F, I).go`) must keep the concrete owner so `I::SHIFT` resolves per
# instantiation instead of collapsing to one specialization.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic_module_self_call_owner_repro.XXXXXX")"
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
module IA
  SHIFT = 4
end
module IB
  SHIFT = 8
end
module Impl(F, I)
  def self.go(x)
    helper(x) + 1
  end
  def self.helper(x)
    I::SHIFT * 1000 + x
  end
end
LibC.printf("%d %d\n", Impl(Int32, IA).go(5), Impl(Int64, IB).go(5))
CR
check c1 '4006 8006'

cat >"$WORK_DIR/c2.cr" <<'CR'
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
  private module ImplInfo_Float32
    extend Meths(self)
    SHIFT = 8
    alias CarrierUInt = UInt32
  end
  private module Impl(F, ImplInfo)
    def self.go(x)
      if x == 0
        return 100
      else
        helper(x.to_i32!) + 1
      end
    end
    def self.helper(x)
      ImplInfo::SHIFT * 1000 + x
    end
  end
  {% for f, uint in {Float64 => UInt64, Float32 => UInt32} %}
    def self.run(x : {{ uint }})
      Impl({{ f }}, ImplInfo_{{ f }}).go(x)
    end
  {% end %}
end
LibC.printf("%d %d\n", Outer::Box.run(256_u64), Outer::Box.run(256_u32))
CR
check c2 '4257 8257'

if [ "$status" -ne 0 ]; then
  echo "FAIL: generic module self-call lost the concrete owner" >&2
  exit 1
fi
echo "PASS: generic module self-calls keep the concrete owner"
