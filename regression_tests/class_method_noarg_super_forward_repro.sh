#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-bin/adamas}"
tmpdir="${TMPDIR:-/tmp}/adamas_class_super_forward_$$"
mkdir -p "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

src="$tmpdir/class_method_noarg_super_forward.cr"
bin="$tmpdir/class_method_noarg_super_forward"
log="$tmpdir/compile.log"

cat > "$src" <<'CR'
class Parent
  def self.ping
    7
  end
end

class Child < Parent
  def self.ping
    super
  end
end

puts Child.ping
CR

if ! "$compiler" "$src" -o "$bin" > "$log" 2>&1; then
  cat "$log"
  exit 1
fi

echo "class_method_noarg_super_forward_compile_ok"
