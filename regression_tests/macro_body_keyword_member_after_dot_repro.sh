#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-bin/adamas}"
tmpdir="$(mktemp -d /tmp/adamas_macro_keyword_member.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/repro.cr" <<'CR'
module MacroKeywordMemberCarrier
  {% for type in [Int32] %}
    private def gen(range : Range({{type}}, {{type}})) : {{type}}
      range.begin &+ range.end
    end
  {% end %}

  def call_gen
    gen(1..2)
  end
end

class MacroKeywordMemberUser
  include MacroKeywordMemberCarrier
end

puts MacroKeywordMemberUser.new.call_gen
CR

"$compiler" "$tmpdir/repro.cr" -o "$tmpdir/repro" > "$tmpdir/compile.log" 2>&1
scripts/run_safe.sh "$tmpdir/repro" 5 512 > "$tmpdir/run.log" 2>&1

if ! grep -q '^3$' "$tmpdir/run.log"; then
  cat "$tmpdir/compile.log" >&2
  cat "$tmpdir/run.log" >&2
  exit 1
fi

if grep -q 'STUB CALLED' "$tmpdir/run.log"; then
  cat "$tmpdir/run.log" >&2
  exit 1
fi

echo "macro_body_keyword_member_after_dot_ok"
