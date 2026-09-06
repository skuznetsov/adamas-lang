#!/usr/bin/env bash
# String literal macro members must emit code and retain source token gaps.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/macro-literal-yield.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/literal.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def visit(&)
  current = 7
  {% if true %}
    {{ "yield current".id }}
  {% end %}
end
result = 0
visit { |n| result = n }
LibC.exit(result - 7)
CR
cat > "$work/postfix.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
def visit(active : Bool, &)
  current = 7
  {% if true %}
    {{ "yield current".id }} if active
  {% end %}
end
result = 0
visit(false) { |n| result += n }
LibC.exit(11) unless result == 0
visit(true) { |n| result += n }
LibC.exit(12) unless result == 7
LibC.exit(0)
CR
cat > "$work/range.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
calls = 0
found = (0...2).any? { |n| calls += 1; n == 1 }
LibC.exit(11) unless found && calls == 2
calls = 0
found = (0...2).any? { |n| calls += 1; false }
LibC.exit(12) unless !found && calls == 2
calls = 0
found = (0..0).any? { |n| calls += 1; n == 0 }
LibC.exit(13) unless found && calls == 1
calls = 0
found = (0...0).any? { |n| calls += 1; true }
LibC.exit(14) unless !found && calls == 0
LibC.exit(0)
CR
for name in literal postfix range; do
  flags=()
  [[ "$name" == range ]] || flags+=(--no-prelude)
  if ! "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/$name.cr" "${flags[@]}" -o "$work/$name" > "$work/$name.log" 2>&1; then
    cat "$work/$name.log"
    exit 1
  fi
  if ! "$root/scripts/run_safe.sh" "$work/$name" 5 512 >> "$work/$name.log" 2>&1; then
    cat "$work/$name.log"
    exit 1
  fi
  echo "PASS[$name]"
done
