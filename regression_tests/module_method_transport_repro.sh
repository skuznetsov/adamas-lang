#!/usr/bin/env bash
# Module method lookup must preserve generic punctuation and included bodies.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module_method_transport.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/generic-module-simple.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Query(T)
  def value : Int32
    42
  end
end
class Box(T)
  include Query(T)
end
LibC.exit(21) unless Box(Int32).new.value == 42
LibC.exit(0)
CR
cat >"$WORK_DIR/nongeneric-class-module.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Query
  def value : Int32
    42
  end
end
class Box
  include Query
end
LibC.exit(21) unless Box.new.value == 42
LibC.exit(0)
CR
cat >"$WORK_DIR/array-optional-module.cr" <<'CR'
module Indexable(T)
  def []?(index : Int32)
    if index >= 0 && index < size
      self[index]
    else
      nil
    end
  end
end
class Array(T)
  include Indexable(T)
end
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Entry
  @value : Int32
  def initialize(@value : Int32)
  end
  def value : Int32
    @value
  end
end
class Table
  @entries : Array(Entry)
  def initialize(@entries : Array(Entry))
  end
  def first : Int32
    if entry = @entries[0]?
      entry.value
    else
      -1
    end
  end
end
LibC.exit(21) unless Table.new([Entry.new(42)]).first == 42
LibC.exit(22) unless Table.new([] of Entry).first == -1
LibC.exit(0)
CR
for name in generic-module-simple nongeneric-class-module array-optional-module; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 --no-prelude \
    "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name" >"$WORK_DIR/build.log" 2>&1; then
    cat "$WORK_DIR/build.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/run.log" 2>&1; then
    cat "$WORK_DIR/run.log" >&2
    exit 1
  fi
done
echo module_method_transport_repro_ok
