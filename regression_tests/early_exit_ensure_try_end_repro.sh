#!/usr/bin/env bash
# `break`/`next` out of a loop, an inline-yield block, or a block body that sits
# inside `begin ... ensure/rescue` must run the ensure body and pop the rescue
# handler (TryEnd). Early exits skipped both: ensure never ran and
# `__crystal_exc_depth` leaked one slot per exit, overflowing the 64-entry
# setjmp stack (stage3 build died with exit 138 in a hot loop).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/early_exit_ensure_try_end_repro.XXXXXX")"
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

def f_break
  i = 0
  while true
    begin
      break
    ensure
      LibC.printf("ens-break\n")
    end
  end
end

def f_next
  i = 0
  while i < 1
    i += 1
    begin
      next
    ensure
      LibC.printf("ens-next\n")
    end
  end
end

def wrap
  begin
    yield
  ensure
    LibC.printf("ens-wrap\n")
  end
end

f_break
f_next
wrap { 1 }
[1].each do |v|
  begin
    next
  ensure
    LibC.printf("ens-blocknext\n")
  end
end
[1].each do |v|
  begin
    break
  ensure
    LibC.printf("ens-blockbreak\n")
  end
end
def brk
  wrap { break 5 }
  LibC.printf("after-brk\n")
end
brk
CR
check c1 'ens-break
ens-next
ens-wrap
ens-blocknext
ens-blockbreak
ens-wrap
after-brk'

if [ "$status" -ne 0 ]; then
  echo "FAIL: early exit skipped ensure/TryEnd" >&2
  exit 1
fi
echo "PASS: early exits run ensure and pop rescue handlers"
