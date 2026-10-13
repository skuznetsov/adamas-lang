#!/usr/bin/env bash
# An alias to a generic instance used as a value (`alias AG = G(Foo)`,
# `"#{AG}"`, `AG.k`) fell through to an undefined local: the alias target
# is not a registered type name until monomorphized, and
# lower_type_literal_from_name resolved aliases only on the non-generic path.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic_alias_value.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_generic_alias.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
  fun strlen(s : UInt8*) : UInt64
end

class Abcde
end

class G(T)
  def self.k
    3
  end
end

module M
  alias MG = G(Abcde)
end

alias AA = Abcde
alias AG = G(Abcde)
s = "#{AA}|#{AG}|#{M::MG}"
ok = LibC.strlen(s.to_unsafe) == 23 && AG.k + M::MG.k == 6
LibC.exit(ok ? 0 : 1)
CR
cat >"$WORK_DIR/generic_alias.cr" <<'CR'
alias AI = Array(Int32)
a = AI.new
a << 4
exit("#{AI}" == "Array(Int32)" && a.size == 1 ? 0 : 1)
CR
for name in np_generic_alias generic_alias; do
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
echo generic_alias_type_literal_repro_ok
