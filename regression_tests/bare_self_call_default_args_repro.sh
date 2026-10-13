#!/usr/bin/env bash
# A bare self-call with no positional args (`asc_num?` inside `num?`) must fill
# declared defaults like `self.asc_num?` does. It targeted the zero-arg mangle and
# the defaulted `base` param only got backend padding; in stage2 the default
# literal was lost, so `base` was 0 (S3 "Invalid base" abort).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bare_self_call_default_args_repro.XXXXXX")"
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
struct Char
  def asc_num?(base : Int = 10) : Bool
    !!toi?(base)
  end
  def num? : Bool
    asc_num?
  end
  def alnum? : Bool
    num?
  end
  def toi?(base : Int = 10) : Int32?
    LibC.printf("base=%d\n", base)
    return nil unless 2 <= base <= 36
    1
  end
end
c = 'a'
LibC.printf("r=%d\n", c.alnum? ? 1 : 0)
LibC.printf("r2=%d\n", c.asc_num?(16) ? 1 : 0)
CR
check c1 'base=10
r=1
base=16
r2=1'

# Runtime output alone does not discriminate in stage1 (backend padding supplies
# the default literal); the HIR call must carry the default argument itself.
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/c1.cr" --no-prelude --emit hir -o "$WORK_DIR/c1h" >"$WORK_DIR/c1h.build.log" 2>&1; then
  echo "FAIL[hir]: --emit hir failed" >&2
  status=1
elif ! grep -q 'call .*Char#asc_num?\$Int32(%' "$WORK_DIR/c1h.hir"; then
  echo "FAIL[hir]: no Char#asc_num?\$Int32 call (probe not exercised)" >&2
  status=1
elif grep -q 'call .*Char#asc_num?\$Int32()' "$WORK_DIR/c1h.hir"; then
  echo "FAIL[hir]: bare self-call targets Char#asc_num?\$Int32 with no default arg" >&2
  status=1
fi

if [ "$status" -ne 0 ]; then
  echo "FAIL: bare self-call dropped declared default args" >&2
  exit 1
fi
echo "PASS: bare self-call fills declared default args"
