#!/usr/bin/env bash
# String#inspect must use Object#inspect's builder and concrete inspect(io).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/string-inspect-super.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/inspect.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def sample : String
  "Seven"
end
LibC.exit(11) unless sample.inspect == "\"Seven\""
LibC.exit(12) unless "".inspect == "\"\""
LibC.exit(13) unless "a\n\"\\".inspect == "\"a\\n\\\"\\\\\""
LibC.exit(14) unless sample.inspect == "\"Seven\""
LibC.exit(0)
CR
# Full prelude is intentional: this exercises the unmodified stdlib super chain.
if ! "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/inspect.cr" -o "$work/inspect" > "$work/inspect.log" 2>&1; then
  cat "$work/inspect.log"
  exit 1
fi
if ! "$root/scripts/run_safe.sh" "$work/inspect" 5 512 >> "$work/inspect.log" 2>&1; then
  cat "$work/inspect.log"
  exit 1
fi
echo 'PASS[string-inspect-super]'
