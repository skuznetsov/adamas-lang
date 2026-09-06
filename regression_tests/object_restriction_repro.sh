#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 COMPILER" >&2
  exit 2
fi

compiler="$1"
original_crystal="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

run_safe="$repo_root/scripts/run_safe.sh"

if [ ! -x "$compiler" ]; then
  echo "compiler is not executable: $compiler" >&2
  exit 2
fi
if [ ! -x "$original_crystal" ]; then
  echo "original Crystal is not executable: $original_crystal" >&2
  exit 2
fi
if [ ! -x "$run_safe" ]; then
  echo "run_safe.sh is not executable: $run_safe" >&2
  exit 2
fi

work_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/adamas-object-restriction.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
export CRYSTAL_CACHE_DIR="$work_dir/crystal-cache"
mkdir -p "$CRYSTAL_CACHE_DIR"

cat > "$work_dir/direct.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Descriptor
  getter value : Int32

  def initialize(@value : Int32); end

  def ==(other : Descriptor) : Bool
    value == other.value
  end

  def ==(other : Int32) : Bool
    false
  end
end

def compare(needle : Object) : Bool
  Descriptor.new(7) == needle
end

LibC.exit(1) unless compare(Descriptor.new(7))
LibC.exit(2) if compare(7)
LibC.exit(0)
CR

cat > "$work_dir/wrapper.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Descriptor
  getter value : Int32

  def initialize(@value : Int32); end

  def ==(other : Descriptor) : Bool
    value == other.value
  end

  def ==(other : Int32) : Bool
    false
  end
end

def contains(values : Slice(Descriptor), needle : Object) : Bool
  values.includes?(needle)
end

item = Descriptor.new(7)
items = Slice(Descriptor).new(1) { item }
LibC.exit(11) unless item == Descriptor.new(7)
LibC.exit(12) if item == 7
LibC.exit(13) unless contains(items, Descriptor.new(7))
LibC.exit(14) if contains(items, 7)
LibC.exit(0)
CR

cat > "$work_dir/nil.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Descriptor
  getter value : Int32

  def initialize(@value : Int32); end

  def ==(other : Descriptor) : Bool
    value == other.value
  end

  def ==(other : Int32) : Bool
    false
  end
end

def compare(needle : Object) : Bool
  Descriptor.new(7) == needle
end

LibC.exit(1) if compare(nil)
LibC.exit(0)
CR

compile_with() {
  local label="$1"
  local compiler_path="$2"
  shift 2
  local log="$work_dir/$label.compile.log"
  set +e
  "$run_safe" "$compiler_path" 180 8192 "$@" >"$log" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL $label compile: exit $rc" >&2
    cat "$log" >&2
    exit 1
  fi
}

run_expected() {
  local label="$1"
  local expected="$2"
  local binary="$3"
  local log="$work_dir/$label.runtime.log"
  set +e
  "$run_safe" "$binary" 10 512 >"$log" 2>&1
  local actual=$?
  set -e
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL $label: expected exit $expected, got $actual" >&2
    cat "$log" >&2
    exit 1
  fi
  echo "PASS $label: exit $actual"
}

for fixture in direct wrapper nil; do
  # This corridor needs the real Object hierarchy and Slice iteration bodies.
  # Without prelude the restricted wrapper currently has a separate bodyless
  # compare$Descriptor target and cannot serve as this specialization oracle.
  compile_with "adamas-$fixture" "$compiler" "$work_dir/$fixture.cr" -o "$work_dir/adamas-$fixture"
  compile_with "original-$fixture" "$original_crystal" build "$work_dir/$fixture.cr" -o "$work_dir/original-$fixture"
  run_expected "adamas-$fixture" 0 "$work_dir/adamas-$fixture"
  run_expected "original-$fixture" 0 "$work_dir/original-$fixture"
done

echo "Object restriction regression passed for Adamas and original Crystal"
