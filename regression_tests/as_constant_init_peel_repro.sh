#!/usr/bin/env bash
# Regression: a constant whose value is wrapped in `.as T` / parens
# (stdlib `INFINITY = (1_f64 / 0_f64).as Float64`) was classified by the
# wrapper node, never deferred-initialized, and stayed 0.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/as_constant_init_peel_repro.XXXXXX")"
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
struct Float64
  @[::Primitive(:binary)]
  def /(other : Float64) : Float64
  end
  MYINF = (1_f64 / 0_f64).as Float64
  MYINF2 = 1_f64 / 0_f64
end
INF3 = (1_f64 / 0_f64)
LibC.printf("%g %g %g\n", Float64::MYINF, Float64::MYINF2, INF3)
a = 1_f64 / 0_f64
LibC.printf("%g\n", a)
CR
check c1 'inf inf inf
inf'

if [ "$status" -ne 0 ]; then
  echo "FAIL: as-wrapped constant init dropped" >&2
  exit 1
fi
echo "PASS: as-wrapped constant init OK"
