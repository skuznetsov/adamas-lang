#!/usr/bin/env bash
# `"#{Foo}"` on a type literal called the instance `Foo#to_s` (a never-
# lowered stub) and `"#{Int32}"` interpolated the literal's placeholder
# value `0`. Interpolating a type literal must produce the type name.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/type_literal_interp.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_interp.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun strlen(s : UInt8*) : UInt64
end

class Abcde
end

module Mo
end

s = "#{Abcde}|#{Mo}"
LibC.exit(LibC.strlen(s.to_unsafe) == 8 ? 0 : 1)
CR
cat >"$WORK_DIR/interp.cr" <<'CR'
class C
end

class G(T)
end

s = "#{C}|#{Int32}|#{G(Int32)}"
exit(s == "C|Int32|G(Int32)" ? 0 : 1)
CR
for name in np_interp interp; do
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
echo type_literal_string_interpolation_repro_ok
