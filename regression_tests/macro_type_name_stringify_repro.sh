#!/usr/bin/env bash
# `{{ @type.name.stringify }}` in a def body expanded to "" because the
# `@type` receiver of `.name` was evaluated as an opaque AST node value whose
# members are all nil. Every `@type.name` chain must see the owner type, and a
# `Class` instance method must expand `@type` per receiver type (stdlib
# `Class#name` is `{{ @type.name.stringify }}`).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_type_name_stringify.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_def_body.cr" <<'CR'
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

  def self.nm2 : String
    {{ @type.name.stringify }}
  end

  def nm3 : String
    {{ @type.name.stringify }}
  end
end

a = LibC.strlen(Abcde.nm2.to_unsafe)
b = LibC.strlen(Abcde.new.nm3.to_unsafe)
LibC.exit((a == 5 ? 3 : 1) + (b == 5 ? 4 : 0))
CR
cat >"$WORK_DIR/np_class_meta.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun strlen(s : UInt8*) : UInt64
end

class String
  def to_unsafe : UInt8*
    pointerof(@c)
  end
end

class Class
  def nm : String
    {{ @type.name.stringify }}
  end
end

class Abcde
  def initialize
  end
end

class Xy
  def initialize
  end
end

def pp1(o)
  o.nm
end

a = LibC.strlen(Abcde.nm.to_unsafe)
b = LibC.strlen(pp1(Abcde).to_unsafe)
c = LibC.strlen(Xy.nm.to_unsafe)
LibC.exit((a == 5 ? 3 : 1) + (b == 5 ? 4 : 0) + (c == 2 ? 8 : 0))
CR
check() {
  local name="$1" want="$2"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q "^\[EXIT: $want\]" "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT $want):" >&2
    cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
}
check np_def_body 7
check np_class_meta 15
echo macro_type_name_stringify_repro_ok
