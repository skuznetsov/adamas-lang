#!/usr/bin/env bash
# A bare path inside a subtype method (`Pr.go` in `struct F6 < Fl`) must also
# search nested types of the ancestors (`Fl::Pr`), like original Crystal.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ancestor_nested_type_lookup_repro.XXXXXX")"
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

abstract struct Fl
  module Pr
    def self.go(x : Int32) : Int32
      x + 100
    end
  end
end

struct F6 < Fl
  def initialize(@v : Int32)
  end

  def run : Int32
    Pr.go(@v)
  end
end

LibC.printf("%d\n", F6.new(5).run)
CR
check c1 '105'

if [ "$status" -ne 0 ]; then
  echo "FAIL: nested type of an ancestor not found from a subtype" >&2
  exit 1
fi
echo "PASS: ancestor nested type resolved from subtype"
