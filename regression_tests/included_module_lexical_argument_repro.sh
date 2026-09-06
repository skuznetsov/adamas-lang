#!/usr/bin/env bash
# Generic include arguments retain the including owner's lexical identity.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/included-module-lexical.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/record.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Ascending
  record Potential, score : Int32 do
    include Comparable(Potential)
    def <=>(other : Potential)
      score <=> other.score
    end
  end
end
module Descending
  record Potential, score : Int32 do
    include Comparable(Potential)
    def <=>(other : Potential)
      other.score <=> score
    end
  end
end
a = Ascending::Potential.new(1)
b = Ascending::Potential.new(2)
LibC.exit(11) unless a < b
LibC.exit(12) if b < a
LibC.exit(13) if a < a
LibC.exit(17) unless b > a
c = Descending::Potential.new(1)
d = Descending::Potential.new(2)
LibC.exit(14) if c < d
LibC.exit(15) unless d < c
LibC.exit(16) if c < c
LibC.exit(0)
CR
# Stock record/Comparable are necessary here: the no-prelude synthetic module
# control does not reproduce the inherited Object#<=> fallback.
if ! "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/record.cr" -o "$work/record" > "$work/check.log" 2>&1; then
  cat "$work/check.log"
  exit 1
fi
if ! "$root/scripts/run_safe.sh" "$work/record" 5 512 >> "$work/check.log" 2>&1; then
  cat "$work/check.log"
  exit 1
fi
echo 'PASS[record-lexical-owners]'
