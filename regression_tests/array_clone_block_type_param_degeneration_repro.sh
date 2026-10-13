#!/usr/bin/env bash
# `Array(String)#clone` lowers to `Array(T).new(size) { |i| @buffer[i].clone.as(T) }`.
# Two independent defects used to rebind T away from String while lowering that
# block, degenerating the owner to `Array(Array)` (and, once the first defect was
# fixed in isolation, to `Array(Int32)`):
#
#   1. `block_param_types_for_call` took an `X.new { }`-yields-the-receiver
#      shortcut for every constructor, so the block param of
#      `Array.new(size, & : Int32 -> T)` was typed `Array` instead of `Int32`.
#   2. `expr.as(U)` in a block body names the block RETURN type, but both
#      inline-block-return inference and block-to-function lowering used it to
#      bind U := <type of the first block param>, overwriting the enclosing
#      `T => String` binding.
#
# Composition renamed the owner mid-lowering, so `Array(T).build`'s
# `ary.size = ...` was minted as `Array(Array)#size=$Int32`, which has no body:
# either a hard "receiver repair left bodyless target" error or, when the
# degenerate instance happened to exist, silently wrong code.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array-clone-type-param.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

cat >"$WORK_DIR/array_clone.cr" <<'CR'
a = ["x", "y", "z"]
b = a.clone
puts b.size
puts b[0]
b << "w"
puts b.size
puts a.size
CR

BIN="$WORK_DIR/array_clone"
COMPILE_LOG="$WORK_DIR/compile.log"
RUN_LOG="$WORK_DIR/run.log"

# A normal build retains $BIN.ll and links the runtime probe. --emit llvm-ir
# stops after writing IR and cannot supply the executable checked below.
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/array_clone.cr" --no-llvm-cache -o "$BIN" >"$COMPILE_LOG" 2>&1; then
  echo "regression: Array(String)#clone failed to compile" >&2
  tail -40 "$COMPILE_LOG" >&2
  exit 1
fi

# The pre-fix failure mode was a loud diagnostic on an otherwise rc=0 pipeline.
if grep -q 'receiver repair left bodyless target' "$COMPILE_LOG"; then
  echo "regression: receiver repair hit a bodyless target while lowering clone" >&2
  grep -m3 'receiver repair left bodyless target' "$COMPILE_LOG" >&2
  exit 1
fi

LL="$BIN.ll"
if [[ ! -s "$LL" ]]; then
  echo "regression: compilation produced no $LL" >&2
  exit 1
fi
if [[ ! -x "$BIN" ]]; then
  echo "regression: compilation produced no executable $BIN" >&2
  exit 1
fi

# Body of one LLVM function definition, by exact define line prefix.
fn_body() {
  awk -v want="$1" '
    index($0, want) == 1 { inside = 1 }
    inside { print }
    inside && $0 == "}" { exit }
  ' "$LL"
}

clone_body="$(fn_body 'define ptr @Array$LString$R$Hclone(ptr %self)')"
if [[ -z "$clone_body" ]]; then
  echo "regression: Array(String)#clone was not emitted" >&2
  exit 1
fi

# The discriminating check. Every Array instance `clone` touches must be the
# one it is cloning. With defect 2 still live the body allocated an
# `Array(Int32)` (T bound from the block's index param) and stored String
# pointers into it: same machine layout, so the program still printed the right
# values while the IR was type-confused.
foreign="$(grep -o 'call [a-z0-9 ]*@Array\$L[A-Za-z0-9$_]*' <<<"$clone_body" \
  | grep -o '@Array\$L[A-Za-z0-9$_]*' \
  | grep -v '^@Array\$LString\$R' | sort -u || true)"
if [[ -n "$foreign" ]]; then
  echo "regression: Array(String)#clone lowered against a foreign Array instance" >&2
  echo "$foreign" >&2
  exit 1
fi

for want in 'call ptr @Array$LString$R$Dnew$$Int32' \
            'call ptr @Array$LString$R$Hto_unsafe' \
            'call i32 @Array$LString$R$Hsize$SET$$Int32'; do
  grep -qF "$want" <<<"$clone_body" || {
    echo "regression: Array(String)#clone is missing: $want" >&2
    exit 1
  }
done

# `Array$LArray$R` is the degenerate owner `Array(Array)` the first defect
# produced; a legitimate nested instance mangles as `Array$LArray$LString$R$R`
# and does not match.
if grep -q 'Array\$LArray\$R' "$LL"; then
  echo "regression: degenerate owner Array(Array) reached codegen" >&2
  grep -m5 -o 'Array\$LArray\$R[A-Za-z0-9$_]*' "$LL" | sort -u >&2
  exit 1
fi

# Bare generic owners are template keys, never bodies: a call minted against
# `Array#size=` can only become an abort stub.
if grep -q '; ABORT stub for unlowered method: Array\$H' "$LL"; then
  echo "regression: bare generic-owner Array stub emitted" >&2
  grep -m5 '; ABORT stub for unlowered method: Array\$H' "$LL" >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 60 512 >"$RUN_LOG" 2>&1; then
  echo "regression: cloned array binary failed at runtime" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

# clone must copy: 3 / "x" / 4 after the push / 3 for the untouched original.
expected=$'3\nx\n4\n3'
actual="$(grep -v '^\[' "$RUN_LOG" | grep -v '^===' | sed '/^$/d')"
if [[ "$actual" != "$expected" ]]; then
  echo "regression: clone produced the wrong contents" >&2
  echo "expected: ${expected//$'\n'/ | }" >&2
  echo "actual:   ${actual//$'\n'/ | }" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "array_clone_block_type_param_degeneration_ok"
