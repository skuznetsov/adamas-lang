#!/usr/bin/env bash
# `x.as(typeof(local))` inside a namespaced method must cast to the local's
# type. The type resolver treated `typeof` as a generic base and qualified it
# in the owner, so 1.22.1's `data.as(typeof(callstack))` in
# Exception::CallStack.unwind (call_stack/libunwind.cr) became
# Exception::CallStack::Array(Pointer(Void)) and `bt << ip` was undefined.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typeof-cast-namespace.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

struct Pointer(T)
  def self.null : self
    new(0_u64)
  end

  @[Primitive(:pointer_new)]
  def self.new(address : UInt64)
  end
end

struct Proc(*T, R)
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end

class Array(T)
  @size = 0

  def initialize(cap : Int32)
  end

  def <<(x : T) : self
    @size = @size + 1
    self
  end

  def size : Int32
    @size
  end
end
CR

{ cat "$WORK_DIR/header.cr"; cat <<'CR'; } > "$WORK_DIR/method_local.cr"
class Exception
  struct CallStack
    def self.unwind : Array(Void*)
      callstack = Array(Void*).new(32)
      data = callstack.as(Void*)
      bt = data.as(typeof(callstack))
      bt << Pointer(Void).null
      callstack
    end
  end
end

LibC.exit(Exception::CallStack.unwind.size + 41)
CR

{ cat "$WORK_DIR/header.cr"; cat <<'CR'; } > "$WORK_DIR/proc_literal.cr"
module Wrap
  struct CallStack
    def self.unwind : Array(Void*)
      callstack = Array(Void*).new(32)
      fn = ->(data : Void*) do
        bt = data.as(typeof(callstack))
        bt << Pointer(Void).null
        0
      end
      fn.call(callstack.as(Void*))
      callstack
    end
  end
end

LibC.exit(Wrap::CallStack.unwind.size + 41)
CR

CASES=(
  "method_local:42"
  "proc_literal:42"
)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d typeof cast target case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'typeof cast target cases passed\n'
