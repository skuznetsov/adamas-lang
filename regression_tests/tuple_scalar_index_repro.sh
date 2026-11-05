#!/usr/bin/env bash
# Dynamic Tuple indexing must use the type and storage of the selected slot.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
candidate="${1:?usage: tuple_scalar_index_repro.sh <candidate-compiler>}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
if [[ ! -x "$candidate" || ! -x "$original" ]]; then
  echo 'Both Crystal and the candidate compiler must be executable' >&2
  exit 2
fi
if [[ -z "${CRYSTAL_PATH:-}" ]]; then
  installed_path="$("$original" env CRYSTAL_PATH)"
  export CRYSTAL_PATH="${installed_path#lib:}"
fi
work="$(mktemp -d "${TMPDIR:-/tmp}/tuple-scalar-index.XXXXXX")"
cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 || "${KEEP_TMP:-0}" == 1 ]]; then
    echo "kept_work=$work" >&2
  else
    rm -rf "$work"
  fi
}
trap cleanup EXIT
export RUN_SAFE_PASSTHROUGH_STDIO=1

cat >"$work/scalar.cr" <<'CRYSTAL'
def brackets(tuple, index)
  tuple[index]
rescue IndexError
  "bounds"
end

def explicit_brackets(tuple, index)
  tuple.[](index)
rescue IndexError
  "bounds"
end

def at(tuple, index)
  tuple.at(index)
rescue IndexError
  "bounds"
end

def receiver
  puts "receiver"
  {21, "right"}
end

def index
  puts "index"
  1
end

tuple = {21, "right"}
puts typeof(brackets(tuple, 0))
puts brackets(tuple, 0)
puts brackets(receiver, index)
puts brackets(tuple, -2_i8)
puts explicit_brackets(tuple, -1_i8)
puts brackets(tuple, 1_u8)
puts brackets(tuple, 4294967297_u64)
puts brackets(tuple, 4294967297_u128)
puts explicit_brackets(tuple, -4294967297_i64)
puts at(tuple, -1_i16)
puts at(tuple, 4294967297_u64)
puts tuple[-1]
CRYSTAL

cat >"$work/override.cr" <<'CRYSTAL'
struct Tuple
  def [](index : UInt16) : String
    "custom brackets"
  end

  def at(index : Int16) : String
    "custom at"
  end
end

x = 0_u16
y = 0_i16
tuple = {1, "a"}
puts tuple[0]
puts tuple[x]
puts tuple.[](x)
puts tuple[y]
puts tuple.at(y)
CRYSTAL

printf '%s\n' '(Int32 | String)' 21 receiver index right 21 right right \
  bounds bounds bounds right bounds right >"$work/scalar.expected"
printf '%s\n' 1 'custom brackets' 'custom brackets' 'custom at' 'custom at' >"$work/override.expected"

build_and_run() {
  local engine="$1" name="$2"
  local binary="$work/$engine.$name"
  if [[ "$engine" == original ]]; then
    CRYSTAL_CACHE_DIR="$work/original.cache" "$safe" "$original" 120 8192 \
      build "$work/$name.cr" --link-flags=-fuse-ld=/usr/bin/ld -o "$binary"
  else
    ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--L/opt/homebrew/lib -lgc -fuse-ld=/usr/bin/ld}" \
      "$safe" "$candidate" 120 8192 "$work/$name.cr" --no-ast-cache --no-llvm-cache -o "$binary"
  fi >"$binary.build.stdout" 2>"$binary.build.log" || {
    cat "$binary.build.log" >&2
    return 1
  }
  "$safe" "$binary" 5 512 >"$binary.stdout" 2>"$binary.run.log" || {
    cat "$binary.run.log" >&2
    return 1
  }
}

for fixture in scalar override; do
  build_and_run original "$fixture"
  diff -u "$work/$fixture.expected" "$work/original.$fixture.stdout"
  build_and_run candidate "$fixture"
  diff -u "$work/original.$fixture.stdout" "$work/candidate.$fixture.stdout"
done

for expression in 'tuple[false]' 'tuple.[](false)' 'tuple[2]' 'tuple.[](-3)'; do
  printf 'tuple = {21, "right"}\nputs %s\n' "$expression" >"$work/reject.cr"
  original_rc=0
  candidate_rc=0
  CRYSTAL_CACHE_DIR="$work/original.cache" "$safe" "$original" 90 8192 \
    build "$work/reject.cr" --no-codegen >"$work/original.reject.stdout" 2>"$work/original.reject.log" || original_rc=$?
  ADAMAS_LLVM_CACHE=0 "$safe" "$candidate" 90 8192 "$work/reject.cr" \
    --no-ast-cache --no-llvm-cache --no-link --emit hir -o "$work/reject" \
    >"$work/candidate.reject.stdout" 2>"$work/candidate.reject.log" || candidate_rc=$?
  if [[ "$original_rc" -ne 1 || "$candidate_rc" -ne 1 ]]; then
    echo "Unexpected acceptance or crash for $expression ($original_rc, $candidate_rc)" >&2
    cat "$work/original.reject.log" "$work/candidate.reject.log" >&2
    exit 1
  fi
  if [[ "$expression" == *false* ]]; then
    grep -Eq 'expected argument .*Bool' "$work/original.reject.log"
    grep -Eq 'no overload matches Tuple.*Bool' "$work/candidate.reject.log"
  else
    grep -q 'index out of bounds' "$work/original.reject.log"
    grep -q 'index out of bounds' "$work/candidate.reject.log"
  fi
done

cat >"$work/private_index.cr" <<'CRYSTAL'
struct Tuple
  private def [](index : UInt16) : String
    "private"
  end
end

index = 0_u16
tuple = {1, "right"}
puts tuple[index]
CRYSTAL

original_rc=0
candidate_rc=0
CRYSTAL_CACHE_DIR="$work/original.cache" "$safe" "$original" 90 8192 \
  build "$work/private_index.cr" --no-codegen >"$work/original.private.stdout" 2>"$work/original.private.log" || original_rc=$?
ADAMAS_LLVM_CACHE=0 "$safe" "$candidate" 90 8192 "$work/private_index.cr" \
  --no-ast-cache --no-llvm-cache --no-link --emit hir -o "$work/reject" \
  >"$work/candidate.private.stdout" 2>"$work/candidate.private.log" || candidate_rc=$?
if [[ "$original_rc" -ne 1 || "$candidate_rc" -ne 1 ]]; then
  echo "Unexpected acceptance or crash for private index ($original_rc, $candidate_rc)" >&2
  cat "$work/original.private.log" "$work/candidate.private.log" >&2
  exit 1
fi
grep -Fq "private method '[]'" "$work/original.private.log"
grep -Fq "private method '[]'" "$work/candidate.private.log"

echo 'PASS: dynamic Tuple scalar indexing and overload selection match Crystal'
