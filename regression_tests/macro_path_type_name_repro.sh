#!/usr/bin/env bash
# `{{ Abcde.name.stringify }}` / `{{ Mm::Inner.name.stringify }}` expanded to
# "" because a constant path receiver of a macro member access was only looked
# up as a macro variable; a path naming a type must evaluate as a TypeNode
# whose `.name` is the fully qualified type name, also as a call receiver
# (`Gx.name(generic_args: false)`).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_path_type_name.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_path_name.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun strlen(s : UInt8*) : UInt64
end

class String
  def to_unsafe : UInt8*
    pointerof(@c)
  end
end

class Abcde
  def initialize
  end
end

class Gx(T)
end

module Mm
  class Inner
  end

  def self.inner_name : String
    {{ Inner.name.stringify }}
  end
end

a = LibC.strlen({{ Abcde.name.stringify }}.to_unsafe)
b = LibC.strlen({{ Mm::Inner.name.stringify }}.to_unsafe)
c = LibC.strlen(Mm.inner_name.to_unsafe)
d = LibC.strlen({{ Gx.name(generic_args: false).stringify }}.to_unsafe)
e = LibC.strlen({{ Gx.name.stringify }}.to_unsafe)
LibC.exit((a == 5 ? 3 : 1) + (b == 9 ? 4 : 0) + (c == 9 ? 8 : 0) + (d == 2 ? 16 : 0) + (e == 5 ? 32 : 0))
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/np_path_name.cr" --no-prelude -o "$WORK_DIR/np_path_name" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/np_path_name" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q "^\[EXIT: 63\]" "$WORK_DIR/run.log"; then
  echo "np_path_name failed (want EXIT 63):" >&2
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
# Same lookup inside macro bodies (macro call expansion, macro-generated defs).
cat >"$WORK_DIR/np_body_name.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun strlen(s : UInt8*) : UInt64
end

class String
  def to_unsafe : UInt8*
    pointerof(@c)
  end
end

class Abcde
end

macro abc_name
  {{ Abcde.name.stringify }}
end

class Host
  macro def_named
    def self.nm : String
      {{ Abcde.name.stringify }}
    end
  end
  def_named
end

a = LibC.strlen(abc_name.to_unsafe)
b = LibC.strlen(Host.nm.to_unsafe)
LibC.exit((a == 5 ? 3 : 1) + (b == 5 ? 4 : 0))
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/np_body_name.cr" --no-prelude -o "$WORK_DIR/np_body_name" >"$WORK_DIR/build2.log" 2>&1; then
  cat "$WORK_DIR/build2.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/np_body_name" 5 512 >"$WORK_DIR/run2.log" 2>&1 || true
if ! grep -q "^\[EXIT: 7\]" "$WORK_DIR/run2.log"; then
  echo "np_body_name failed (want EXIT 7):" >&2
  cat "$WORK_DIR/run2.log" >&2
  exit 1
fi
echo macro_path_type_name_repro_ok
