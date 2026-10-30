#!/usr/bin/env bash
# A yielded-block fallback transports the selected callback with its lexical
# environment. Same-named locals in the wrapper and caller remain distinct.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$SAFE" && -x "$ORIGINAL" ]] || exit 2
[[ "${ORIGINAL_ONLY:-0}" == 1 || -x "$CANDIDATE" ]] || exit 2
WORK="$(mktemp -d "${TMPDIR:-/tmp}/forwarded-yield-environment.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK/cache"
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

write_source() {
  cat > "$WORK/$1.cr" <<'CRYSTAL'
lib ForwardOutput
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def consume(value : Int32, &) : Int32
  return yield value
end
CRYSTAL
  case "$1" in
    capture)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def forward(value : Int32, &) : Int32
  consume(value) { |number| yield number }
end
saved = 65
result = forward(0) { |number| ForwardOutput.putchar(saved); number }
ForwardOutput.exit(result)
CRYSTAL
      ;;
    collision)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def forward(value : Int32, &) : Int32
  consume(0) do |number|
    ForwardOutput.putchar(value)
    yield number
  end
end
value = 65
result = forward(66) { |number| ForwardOutput.putchar(value); number }
ForwardOutput.exit(result)
CRYSTAL
      ;;
    nested)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def middle(value : Int32, &) : Int32
  consume(0) { |number| ForwardOutput.putchar(value); yield number }
end
def forward(value : Int32, &) : Int32
  middle(67) { |number| ForwardOutput.putchar(value); yield number }
end
value = 65
result = forward(66) { |number| ForwardOutput.putchar(value); number }
ForwardOutput.exit(result)
CRYSTAL
      ;;
    mutation)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def forward(value : Int32, &) : Int32
  consume(value) { |number| yield number }
end
saved = 65
result = forward(0) do |number|
  ForwardOutput.putchar(saved)
  saved = 66
  number
end
ForwardOutput.putchar(saved)
ForwardOutput.exit(result)
CRYSTAL
      ;;
    returns)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def forward(value : Int32, &) : Int32
  consume(value) { |number| yield number }
end
def owner : Int32
  forward(41) { |number| return 0 }
  42
end
ForwardOutput.exit(owner)
CRYSTAL
      ;;
    break_operand|next_operand)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def iterate(&)
  yield
end
CRYSTAL
      local jump=break
      [[ "$1" == next_operand ]] && jump=next
      cat >> "$WORK/$1.cr" <<CRYSTAL
def forward(value : Int32, &) : Int32
  while true
    iterate { $jump yield value }
  end
  42
end
def owner : Int32
  forward(41) { |number| return 0 }
  42
end
ForwardOutput.exit(owner)
CRYSTAL
      ;;
    nested_returns|nested_breaks)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def middle(value : Int32, &) : Int32
  consume(value) { |number| yield number }
end
def forward(value : Int32, &) : Int32
  middle(value) { |number| yield number }
end
CRYSTAL
      if [[ "$1" == nested_returns ]]; then
        cat >> "$WORK/$1.cr" <<'CRYSTAL'
def owner : Int32
  forward(41) { |number| return 0 }
  42
end
ForwardOutput.exit(owner)
CRYSTAL
      else
        cat >> "$WORK/$1.cr" <<'CRYSTAL'
result = forward(41) { |number| break 0 }
ForwardOutput.exit(result)
CRYSTAL
      fi
      ;;
    breaks)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def forward(value : Int32, &) : Int32
  consume(value) { |number| yield number }
end
result = forward(41) { |number| break 0 }
ForwardOutput.exit(result)
CRYSTAL
      ;;
    rebound)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def relay(&block : Int32 -> Int32) : Int32
  block = ->(number : Int32) { ForwardOutput.putchar(66); number }
  consume(0) { |number| yield number }
end
result = relay { |number| ForwardOutput.putchar(65); number }
ForwardOutput.exit(result)
CRYSTAL
      ;;
    declared_local)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def relay(&block : Int32 -> Int32) : Int32
  block : Proc(Int32, Int32) = ->(number : Int32) { ForwardOutput.putchar(66); number }
  consume(0) { |number| yield number }
end
result = relay { |number| ForwardOutput.putchar(65); number }
ForwardOutput.exit(result)
CRYSTAL
      ;;
    collision_mutation)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
def forward(value : Int32, &) : Int32
  consume(0) { |number| ForwardOutput.putchar(value); yield number }
end
value = 65
result = forward(67) do |number|
  ForwardOutput.putchar(value)
  value = 66
  number
end
ForwardOutput.putchar(value)
ForwardOutput.exit(result)
CRYSTAL
      ;;
    receiver)
      cat >> "$WORK/$1.cr" <<'CRYSTAL'
class Wrapper
  def initialize(@code : Int32)
  end
  def forward(value : Int32, &) : Int32
    consume(value) { |number| ForwardOutput.putchar(@code); yield number }
  end
end
class Caller
  def initialize(@code : Int32)
  end
  def run : Int32
    Wrapper.new(66).forward(0) { |number| ForwardOutput.putchar(@code); number }
  end
end
ForwardOutput.exit(Caller.new(65).run)
CRYSTAL
      ;;
  esac
}

run_safe() {
  local label="$1"; shift
  RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK/$label.resources" \
    "$SAFE" "$@" > "$WORK/$label.stdout" 2> "$WORK/$label.log" || {
    cat "$WORK/$label.log" >&2; return 1;
  }
  rg -q '^\[EXIT: 0\]' "$WORK/$label.log" || {
    cat "$WORK/$label.log" >&2; return 1;
  }
}

for name in ${FORWARDED_YIELD_CASES:-capture collision nested mutation collision_mutation returns breaks nested_returns nested_breaks break_operand next_operand receiver rebound declared_local}; do
  write_source "$name"
  case "$name" in
    capture|declared_local) expected=A ;;
    collision|receiver) expected=BA ;;
    nested) expected=CBA ;;
    mutation) expected=AB ;;
    collision_mutation) expected=CAB ;;
    rebound) expected=B ;;
    returns|breaks|nested_returns|nested_breaks|break_operand|next_operand) expected= ;;
  esac
  printf '%s' "$expected" > "$WORK/$name.expected"
  run_safe "original-$name-build" "$ORIGINAL" 90 4096 build "$WORK/$name.cr" \
    --prelude=empty --no-debug --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK/original-$name"
  run_safe "original-$name-run" "$WORK/original-$name" 5 512
  diff -u "$WORK/$name.expected" "$WORK/original-$name-run.stdout"
  echo "PASS[original/$name]"
  [[ "${ORIGINAL_ONLY:-0}" == 1 ]] && continue
  for mode in lazy eager; do
    if [[ "$mode" == eager ]]; then
      export ADAMAS_EAGER_HIR=1
    else
      unset ADAMAS_EAGER_HIR
    fi
    run_safe "$mode-$name-build" "$CANDIDATE" 120 8192 \
      "$WORK/$name.cr" --prelude=empty --no-ast-cache --no-llvm-cache -o "$WORK/$mode-$name"
    run_safe "$mode-$name-run" "$WORK/$mode-$name" 5 512
    diff -u "$WORK/original-$name-run.stdout" "$WORK/$mode-$name-run.stdout"
    echo "PASS[$mode/$name]"
  done
done

# A concrete captured callback keeps its input contract as well as its carrier.
write_source rejected_input
cat >> "$WORK/rejected_input.cr" <<'CRYSTAL'
def forward(&block : Int32 -> Int32) : Int32
  consume(0) { |number| yield "wrong" }
end
result = forward { |number| number }
ForwardOutput.exit(result)
CRYSTAL
reject_source() {
  local label="$1"; shift
  if RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$@" \
    > "$WORK/$label.stdout" 2> "$WORK/$label.log"; then
    echo "FAIL[$label]: invalid callback input was accepted" >&2
    return 1
  fi
  rg -q '^\[EXIT: 1\]' "$WORK/$label.log" || {
    cat "$WORK/$label.log" >&2; return 1;
  }
  rg -q "${REJECT_PATTERN:-String|Int32}" "$WORK/$label.stdout" "$WORK/$label.log"
  echo "PASS[$label]"
}
reject_source original-rejected-input "$ORIGINAL" 90 4096 build "$WORK/rejected_input.cr" \
  --prelude=empty --no-debug --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK/original-rejected-input"
if [[ "${ORIGINAL_ONLY:-0}" != 1 ]]; then
  for mode in lazy eager; do
    if [[ "$mode" == eager ]]; then
      export ADAMAS_EAGER_HIR=1
    else
      unset ADAMAS_EAGER_HIR
    fi
    reject_source "$mode-rejected-input" "$CANDIDATE" 120 8192 \
      "$WORK/rejected_input.cr" --prelude=empty --no-ast-cache --no-llvm-cache -o "$WORK/$mode-rejected-input"
  done
fi

# First-class source blocks cannot represent a non-local return, even when
# the method also yields. The normal callback path must preserve this error.
cat > "$WORK/rejected_return.cr" <<'CRYSTAL'
lib ForwardOutput
  fun exit(status : Int32) : NoReturn
end
def stored(&block : -> Int32) : Int32
  saved = block
  yield
end
def owner : Int32
  stored { return 0 }
  42
end
ForwardOutput.exit(owner)
CRYSTAL
REJECT_PATTERN='return from captured block' reject_source original-rejected-return "$ORIGINAL" 90 4096 \
  build "$WORK/rejected_return.cr" --prelude=empty --no-debug \
  --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK/original-rejected-return"
if [[ "${ORIGINAL_ONLY:-0}" != 1 ]]; then
  for mode in lazy eager; do
    if [[ "$mode" == eager ]]; then
      export ADAMAS_EAGER_HIR=1
    else
      unset ADAMAS_EAGER_HIR
    fi
    REJECT_PATTERN='return from captured block' reject_source "$mode-rejected-return" "$CANDIDATE" 120 8192 \
      "$WORK/rejected_return.cr" --prelude=empty --no-ast-cache --no-llvm-cache -o "$WORK/$mode-rejected-return"
  done
fi
