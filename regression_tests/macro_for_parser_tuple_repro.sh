#!/usr/bin/env bash
# The parser's bare tuple-returning call must retain its nullable iterable.
# Run with a source-built compiler to cover the parser's generated tuple ABI.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/macro-for-parser-tuple.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/loop.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
macro make
  {% for n, index in [17, 23] %}
    def generated_{{index}} : Int32
      {{n}}
    end
  {% end %}
end
macro make_empty
  {% for n in [] %}
    LibC.exit(99)
  {% end %}
end
make
make_empty
LibC.exit(11) unless generated_0 == 17
LibC.exit(12) unless generated_1 == 23
LibC.exit(0)
CR
if ! "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/loop.cr" --no-prelude -o "$work/loop" > "$work/loop.log" 2>&1; then
  cat "$work/loop.log"
  exit 1
fi
if ! "$root/scripts/run_safe.sh" "$work/loop" 5 512 >> "$work/loop.log" 2>&1; then
  cat "$work/loop.log"
  exit 1
fi
echo 'PASS[macro-for-parser-tuple]'
