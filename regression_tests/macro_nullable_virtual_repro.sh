#!/usr/bin/env bash
# Produced compiler must dispatch rest.size to MacroArrayValue for Nil named args.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/macro-nullable-virtual.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/macros.cr" <<'CR'
macro count(first, *rest)
  {{rest.size}}
end
macro fixed(first, second, third)
  {{second}}
end
CR
for entry in 'empty|count(Foo)|0' 'two|count(Foo, 1, 2)|2' 'fixed|fixed(Foo, 41, 42)|41'; do
  IFS='|' read -r name expression expected <<< "$entry"
  cat > "$work/$name.cr" <<CR
require "./macros"
lib LibC
  fun exit(status : Int32) : NoReturn
end
LibC.exit($expression - $expected)
CR
  if ! "$root/scripts/run_safe.sh" "$compiler" 60 8192 "$work/$name.cr" --no-prelude -o "$work/$name" > "$work/$name.log" 2>&1; then
    cat "$work/$name.log"
    exit 1
  fi
  if ! "$root/scripts/run_safe.sh" "$work/$name" 5 512 >> "$work/$name.log" 2>&1; then
    cat "$work/$name.log"
    exit 1
  fi
  echo "PASS[$name]"
done
