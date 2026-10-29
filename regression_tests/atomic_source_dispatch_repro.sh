#!/usr/bin/env bash
# Source method identity must survive names containing Atomic. Only Ops
# primitives may replace their source calls with MIR atomic instructions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal)}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/atomic-source-dispatch.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/common.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Int32
  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
end
CR

cases=(prefix_get suffix_set namespaced_swap owner_cas exact_source_owner)
cat "$WORK_DIR/common.cr" > "$WORK_DIR/prefix_get.cr"
cat >> "$WORK_DIR/prefix_get.cr" <<'CR'
struct AtomicLike(T)
  def initialize(@value : T)
  end
  def get : Int32
    17
  end
end
LibC.exit(AtomicLike(Int32).new(41).get)
CR

cat "$WORK_DIR/common.cr" > "$WORK_DIR/suffix_set.cr"
cat >> "$WORK_DIR/suffix_set.cr" <<'CR'
struct MyAtomic(T)
  def initialize(@value : T)
  end
  def set(value : T, ordering : Symbol) : Int32
    17
  end
end
LibC.exit(MyAtomic(Int32).new(41).set(9, :relaxed))
CR

cat "$WORK_DIR/common.cr" > "$WORK_DIR/namespaced_swap.cr"
cat >> "$WORK_DIR/namespaced_swap.cr" <<'CR'
module UserSpace
  struct Atomic(T)
    def initialize(@value : T)
    end
    def swap(value : T) : Int32
      17
    end
  end
end
LibC.exit(UserSpace::Atomic(Int32).new(41).swap(9))
CR

cat "$WORK_DIR/common.cr" > "$WORK_DIR/owner_cas.cr"
cat >> "$WORK_DIR/owner_cas.cr" <<'CR'
module AtomicNamespace
  struct Box(T)
    def initialize(@value : T)
    end
    def compare_and_set(expected : T, desired : T) : Int32
      17
    end
  end
end
LibC.exit(AtomicNamespace::Box(Int32).new(41).compare_and_set(41, 9))
CR

# Even the exact owner name is not permission to replace an ordinary method
# body. With an empty prelude these are valid user source declarations.
cat "$WORK_DIR/common.cr" > "$WORK_DIR/exact_source_owner.cr"
cat >> "$WORK_DIR/exact_source_owner.cr" <<'CR'
struct Atomic(T)
  def initialize(@value : T)
  end
  def get : Int32
    17
  end
  def set(value : T) : Int32
    18
  end
  def swap(value : T) : Int32
    19
  end
  def compare_and_set(expected : T, desired : T) : Int32
    20
  end
end
cell = Atomic(Int32).new(41)
LibC.exit(1) unless cell.get == 17
LibC.exit(2) unless cell.set(9) == 18
LibC.exit(3) unless cell.swap(8) == 19
LibC.exit(cell.compare_and_set(7, 6) == 20 ? 17 : 4)
CR

cat "$WORK_DIR/common.cr" > "$WORK_DIR/missing_method.cr"
cat >> "$WORK_DIR/missing_method.cr" <<'CR'
struct Atomic(T)
  def initialize(@value : T)
  end
end
LibC.exit(Atomic(Int32).new(41).get)
CR

compile_case() {
  local compiler="$1" name="$2" binary="$3"
  if [[ "$compiler" == crystal ]]; then
    "$SAFE" "$CRYSTAL_BIN" 120 3072 build "$WORK_DIR/$name.cr" \
      --prelude=empty -o "$binary" > "$binary.build.log" 2>&1
  else
    "$SAFE" "$ADAMAS_BIN" 120 3072 "$WORK_DIR/$name.cr" \
      --no-prelude --no-ast-cache --no-llvm-cache -o "$binary" \
      > "$binary.build.log" 2>&1
  fi
}

for compiler in crystal adamas; do
  for name in "${cases[@]}"; do
    binary="$WORK_DIR/$name.$compiler"
    if ! compile_case "$compiler" "$name" "$binary"; then
      echo "FAIL $name: $compiler build"
      tail -n 14 "$binary.build.log"
      exit 1
    fi
    set +e
    "$SAFE" "$binary" 5 256 > "$binary.run.log" 2>&1
    actual=$?
    set -e
    if [[ "$actual" != 17 ]]; then
      echo "FAIL $name: $compiler exit $actual, expected 17"
      tail -n 12 "$binary.run.log"
      exit 1
    fi
    echo "PASS $compiler $name"
  done
  binary="$WORK_DIR/missing_method.$compiler"
  set +e
  compile_case "$compiler" missing_method "$binary"
  actual=$?
  set -e
  if [[ "$actual" != 1 || -e "$binary" ]] ||
       ! rg -q "undefined method.*get" "$binary.build.log"; then
    echo "FAIL missing_method: $compiler must reject without an executable (exit $actual)"
    tail -n 14 "$binary.build.log"
    exit 1
  fi
  echo "PASS $compiler missing method rejection"
done

echo "PASS: ${#cases[@]} source method cases and one missing-method rejection match original Crystal"
