#!/usr/bin/env bash
# `x = Foo` dropped the type-literal mark on the assigned local, so later
# reads of `x` looked like an instance of Foo: `"#{x}"` called the stub
# instance `Foo#to_s` (and `x = String` interpolated as ""). Assignment
# must carry the mark the same way it carries the runtime type identity.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/type_literal_assign.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_assign.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun strlen(s : UInt8*) : UInt64
end

class Abcde
  def self.foo
    7
  end

  def bar
    5
  end
end

x = Abcde
y = x
s = "#{x}|#{y}"
ok = LibC.strlen(s.to_unsafe) == 11 && x.foo + x.new.bar == 12
LibC.exit(ok ? 0 : 1)
CR
cat >"$WORK_DIR/assign.cr" <<'CR'
x = String
y = x
exit("#{x}|#{y}" == "String|String" ? 0 : 1)
CR
for name in np_assign assign; do
  flags=()
  [[ "$name" == np_* ]] && flags=(--no-prelude)
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
      "$WORK_DIR/$name.cr" ${flags[@]+"${flags[@]}"} -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1; then
    echo "case $name failed:" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo type_literal_assign_mark_repro_ok
