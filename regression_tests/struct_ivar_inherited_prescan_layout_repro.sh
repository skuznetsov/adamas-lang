#!/usr/bin/env bash
# Registration-time ivar inference must see applicable inherited class methods
# when a child has only prescanned methods or only incompatible overloads.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/struct_ivar_inherited_prescan.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/inherited.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class PayloadBox
end

class Base
  def self.make(x : Int32) : PayloadBox
    PayloadBox.new
  end
end

class Derived < Base
end

struct Inner
  def initialize(@pid : Int32)
    @ch = Derived.make(@pid)
    @nb = Derived.make @pid
  end
end

class Outer
  @info : Inner
  @wc = 0

  def initialize(pid : Int32)
    @info = Inner.new(pid)
  end

  def wc
    @wc
  end
end

outer = Outer.new(5)
LibC.exit(outer.wc == 0 ? 7 : 40)
CR

cat >"$WORK_DIR/child_different_arity.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class PayloadBox
end

class ChildBox
end

class Base
  def self.make(x : Int32) : PayloadBox
    PayloadBox.new
  end
end

Base.make(1)

class Derived < Base
  def self.make(x : Int32, y : Int32) : ChildBox
    ChildBox.new
  end
end

struct Inner
  def initialize(@pid : Int32)
    @child = Derived.make(@pid)
  end
end

class Outer
  @info : Inner
  @wc = 0

  def initialize(pid : Int32)
    @info = Inner.new(pid)
  end

  def wc
    @wc
  end
end

outer = Outer.new(5)
LibC.exit(outer.wc == 0 ? 7 : 40)
CR

compile_adamas() {
  local label="$1"
  local source="$2"
  local output="$WORK_DIR/${label}.adamas"
  local log="$WORK_DIR/${label}.adamas.compile.log"
  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${label}.adamas.compile.resources" \
      "$SAFE_RUNNER" "$COMPILER" 300 8192 "$source" --no-prelude --no-llvm-cache -o "$output" >"$log" 2>&1; then
    cat "$log" >&2
    return 1
  fi
  printf '%s\n' "$output"
}

expect_exit() {
  local label="$1"
  local binary="$2"
  local expected="$3"
  local log="$WORK_DIR/${label}.run.log"
  local status=0
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/${label}.run.resources" \
    "$SAFE_RUNNER" "$binary" 5 512 >"$log" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]] || ! grep -q "^\[EXIT: ${expected}\]" "$log"; then
    echo "$label: expected EXIT $expected" >&2
    cat "$log" >&2
    return 1
  fi
}

for case_name in inherited child_different_arity; do
  source="$WORK_DIR/${case_name}.cr"
  adamas_bin="$(compile_adamas "$case_name" "$source")"
  expect_exit "${case_name}.adamas" "$adamas_bin" 7
done

echo struct_ivar_inherited_prescan_layout_repro_ok
