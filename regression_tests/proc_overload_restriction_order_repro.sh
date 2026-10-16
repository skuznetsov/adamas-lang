#!/usr/bin/env bash
# Compare source-level Proc overload ranking/admission with the pinned original.
# Both compilers must agree on overload selection, Proc result-discard behavior,
# and the accepted/rejected Proc input-restriction directions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${COMPILER:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$RUN_SAFE" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL" ]] || {
  echo "usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0 /path/to/adamas" >&2
  exit 2
}

if [[ -n "${LLVM_ROOT:-}" ]]; then
  PATH="$LLVM_ROOT/bin:$PATH"
  CRYSTAL_LIBRARY_PATH="$LLVM_ROOT/lib${CRYSTAL_LIBRARY_PATH:+:$CRYSTAL_LIBRARY_PATH}"
  export PATH CRYSTAL_LIBRARY_PATH
fi
COMMON_ENV=("ADAMAS_EXTRA_LINK_FLAGS=${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
            "ADAMAS_LLVM_CACHE=${ADAMAS_LLVM_CACHE:-0}")
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  COMMON_ENV+=("CRYSTAL_PATH=$CRYSTAL_PATH")
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proc-overload-order.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/overload_matrix.cr" <<'CRYSTAL'
module ProcRankNoReturnBroadFirst
  def self.select(value : Array(Proc)); "broad"; end
  def self.select(value : Array(Proc(Int32, String))); "strict"; end
end
module ProcRankNoReturnStrictFirst
  def self.select(value : Array(Proc(Int32, String))); "strict"; end
  def self.select(value : Array(Proc)); "broad"; end
end
module ProcRankStringBroadFirst
  def self.select(value : Array(Proc)); "broad"; end
  def self.select(value : Array(Proc(Int32, String))); "strict"; end
end
module ProcRankStringStrictFirst
  def self.select(value : Array(Proc(Int32, String))); "strict"; end
  def self.select(value : Array(Proc)); "broad"; end
end
module ProcRankNilBroadFirst
  def self.select(value : Array(Proc)); "broad"; end
  def self.select(value : Array(Proc(Int32, Nil))); "nil"; end
end
module ProcRankNilStrictFirst
  def self.select(value : Array(Proc(Int32, Nil))); "nil"; end
  def self.select(value : Array(Proc)); "broad"; end
end
module ProcRankNoReturnNilBroadFirst
  def self.select(value : Array(Proc)); "broad"; end
  def self.select(value : Array(Proc(Int32, Nil))); "nil"; end
end
module ProcRankNoReturnNilStrictFirst
  def self.select(value : Array(Proc(Int32, Nil))); "nil"; end
  def self.select(value : Array(Proc)); "broad"; end
end
module ProcRankCrossLeftFirst
  def self.choose(left : Array(Proc(Int32, String)), right : Array(Proc)); "left"; end
  def self.choose(left : Array(Proc), right : Array(Proc(Int32, String))); "right"; end
end
module ProcRankCrossRightFirst
  def self.choose(left : Array(Proc), right : Array(Proc(Int32, String))); "right"; end
  def self.choose(left : Array(Proc(Int32, String)), right : Array(Proc)); "left"; end
end
module ProcRankCrossLossLeftAdaptedFirst
  def self.choose(left : Array(Proc(Int32, String)), right : Array(Proc(Int32, Nil))); "adapted-left"; end
  def self.choose(left : Array(Proc), right : Array(Proc)); "exact-bare"; end
end
module ProcRankCrossLossLeftBareFirst
  def self.choose(left : Array(Proc), right : Array(Proc)); "exact-bare"; end
  def self.choose(left : Array(Proc(Int32, String)), right : Array(Proc(Int32, Nil))); "adapted-left"; end
end
module ProcRankCrossLossRightAdaptedFirst
  def self.choose(left : Array(Proc(Int32, Nil)), right : Array(Proc(Int32, String))); "adapted-right"; end
  def self.choose(left : Array(Proc), right : Array(Proc)); "exact-bare"; end
end
module ProcRankCrossLossRightBareFirst
  def self.choose(left : Array(Proc), right : Array(Proc)); "exact-bare"; end
  def self.choose(left : Array(Proc(Int32, Nil)), right : Array(Proc(Int32, String))); "adapted-right"; end
end
module ProcRankNestedInputAdaptedFirst
  def self.pick(callback : Proc(Proc(Int32, Nil), Int32)); "adapted-input"; end
  def self.pick(callback : Proc); "bare-input"; end
end
module ProcRankNestedInputBareFirst
  def self.pick(callback : Proc); "bare-input"; end
  def self.pick(callback : Proc(Proc(Int32, Nil), Int32)); "adapted-input"; end
end

class ProcOwnerRankBroadFirst(T)
  def choose(values : Array(Proc(Int32, T))); "owner-typed"; end
  def choose(values : Array(Proc)); "owner-bare"; end
end
class ProcOwnerRankBareFirst(T)
  def choose(values : Array(Proc)); "owner-bare"; end
  def choose(values : Array(Proc(Int32, T))); "owner-typed"; end
end

abstract class ProcInputAnimal
end
class ProcInputDog < ProcInputAnimal
end

def accept_abstract_int(callback : Proc(Int, Nil)); "abstract-int"; end
def accept_parent_input(callback : Proc(ProcInputAnimal, Nil)); "parent-formal"; end

never : Proc(Int32, NoReturn) = ->(value : Int32) { raise "never invoked" }
string_proc : Proc(Int32, String) = ->(value : Int32) { "value" }
nil_proc : Proc(Int32, Nil) = ->(value : Int32) { nil }
abstract_int_proc : Proc(Int32, Nil) = ->(value : Int32) { nil }
child_input_proc : Proc(ProcInputDog, Nil) = ->(value : ProcInputDog) { nil }
nested_input_actual : Proc(Proc(Int32, String), Int32) = ->(value : Proc(Int32, String)) { 1 }

puts ProcRankNoReturnBroadFirst.select([never])
puts ProcRankNoReturnStrictFirst.select([never])
puts ProcRankStringBroadFirst.select([string_proc])
puts ProcRankStringStrictFirst.select([string_proc])
puts ProcRankNilBroadFirst.select([nil_proc])
puts ProcRankNilStrictFirst.select([nil_proc])
puts ProcRankNoReturnNilBroadFirst.select([never])
puts ProcRankNoReturnNilStrictFirst.select([never])
puts ProcRankCrossLeftFirst.choose([never], [never])
puts ProcRankCrossRightFirst.choose([never], [never])
puts ProcRankCrossLossLeftAdaptedFirst.choose([string_proc], [string_proc])
puts ProcRankCrossLossLeftBareFirst.choose([string_proc], [string_proc])
puts ProcRankCrossLossRightAdaptedFirst.choose([string_proc], [string_proc])
puts ProcRankCrossLossRightBareFirst.choose([string_proc], [string_proc])
puts ProcRankNestedInputAdaptedFirst.pick(nested_input_actual)
puts ProcRankNestedInputBareFirst.pick(nested_input_actual)
puts ProcOwnerRankBroadFirst(Nil).new.choose([string_proc])
puts ProcOwnerRankBareFirst(Nil).new.choose([string_proc])
puts ProcOwnerRankBroadFirst(String).new.choose([string_proc])
puts ProcOwnerRankBareFirst(String).new.choose([string_proc])
puts accept_abstract_int(abstract_int_proc)
puts accept_parent_input(child_input_proc)
CRYSTAL

cat >"$WORK_DIR/wrong_proc_input_direction.cr" <<'CRYSTAL'
class ProcInputAnimal
end
class ProcInputDog < ProcInputAnimal
end

def accept_child_input(callback : Proc(ProcInputDog, Nil)); "child-formal"; end
parent_input_proc : Proc(ProcInputAnimal, Nil) = ->(value : ProcInputAnimal) { nil }
puts accept_child_input(parent_input_proc)
CRYSTAL

cat >"$WORK_DIR/expected.txt" <<'EXPECTED'
strict
strict
strict
strict
nil
nil
broad
broad
left
right
exact-bare
exact-bare
exact-bare
exact-bare
bare-input
bare-input
owner-bare
owner-bare
owner-typed
owner-typed
abstract-int
parent-formal
EXPECTED

build_and_run() {
  local stage="$1" compiler="$2" source="$3"
  local binary="$WORK_DIR/$stage.bin"
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$compiler" build "$source" -o "$binary" --no-debug
             --link-flags="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
  else
    command=("$compiler" "$source" --no-ast-cache --no-llvm-cache --no-debug -o "$binary")
  fi
  if ! env "${COMMON_ENV[@]}" "CRYSTAL_CACHE_DIR=$WORK_DIR/$stage.cache" \
      "$RUN_SAFE" "${command[0]}" 240 8192 "${command[@]:1}" \
      >"$WORK_DIR/$stage.build.log" 2>&1; then
    tail -35 "$WORK_DIR/$stage.build.log" >&2
    return 1
  fi
  rm -rf "$WORK_DIR/$stage.cache"
  if ! env RUN_SAFE_PASSTHROUGH_STDIO=1 \
      "$RUN_SAFE" "$binary" 15 1024 >"$WORK_DIR/$stage.stdout" \
      2>"$WORK_DIR/$stage.run.log"; then
    tail -35 "$WORK_DIR/$stage.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$stage.run.log"
  diff -u "$WORK_DIR/expected.txt" "$WORK_DIR/$stage.stdout"
}

expect_rejection() {
  local stage="$1" compiler="$2"
  local binary="$WORK_DIR/$stage.bin"
  local -a command
  if [[ "$stage" == original_negative ]]; then
    command=("$compiler" build "$WORK_DIR/wrong_proc_input_direction.cr" -o "$binary" --no-debug
             --link-flags="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
  else
    command=("$compiler" "$WORK_DIR/wrong_proc_input_direction.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$binary")
  fi
  if env "${COMMON_ENV[@]}" "CRYSTAL_CACHE_DIR=$WORK_DIR/$stage.cache" \
      "$RUN_SAFE" "${command[0]}" 240 8192 "${command[@]:1}" \
      >"$WORK_DIR/$stage.build.log" 2>&1; then
    echo "ERROR: $stage unexpectedly accepted parent Proc input for child formal" >&2
    return 1
  fi
  rm -rf "$WORK_DIR/$stage.cache" "$binary"
  grep -Eq 'expected argument #1|no overload matches accept_child_input' "$WORK_DIR/$stage.build.log"
}

# Keep the oracle first so candidate compilation cannot hide an original failure.
build_and_run original "$ORIGINAL_CRYSTAL" "$WORK_DIR/overload_matrix.cr"
build_and_run candidate "$COMPILER" "$WORK_DIR/overload_matrix.cr"
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"
expect_rejection original_negative "$ORIGINAL_CRYSTAL"
expect_rejection candidate_negative "$COMPILER"

printf 'PASS: Proc overload ranking and source input restrictions match Crystal\n'
