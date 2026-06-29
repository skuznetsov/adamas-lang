#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-bin/adamas}"
tmpdir="$(mktemp -d /tmp/adamas_module_macro_for_include.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/repro.cr" <<'CR'
module MacroForIncludedHelper
  def call_gen(x : Int32)
    gen(x)
  end

  {% for type in [Int32] %}
    private def gen(x : {{type}}) : {{type}}
      x + 1
    end
  {% end %}
end

class MacroForIncludedUser
  include MacroForIncludedHelper
end

puts MacroForIncludedUser.new.call_gen(41)
CR

"$compiler" "$tmpdir/repro.cr" -o "$tmpdir/repro" > "$tmpdir/compile.log" 2>&1
scripts/run_safe.sh "$tmpdir/repro" 5 512 > "$tmpdir/run.log" 2>&1

if ! grep -q '^42$' "$tmpdir/run.log"; then
  cat "$tmpdir/compile.log" >&2
  cat "$tmpdir/run.log" >&2
  exit 1
fi

if grep -q 'STUB CALLED' "$tmpdir/run.log"; then
  cat "$tmpdir/run.log" >&2
  exit 1
fi

echo "module_macro_for_include_private_helper_ok"
