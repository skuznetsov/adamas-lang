#!/usr/bin/env bash
# A module included into a generic subclass must win over a superclass def
# (Crystal MRO). Generic instances defer included-module def registration,
# so the parent-chain fallback resolved Sub(Int32)#foo to Base1#foo, and
# Array(T)#hash fell to Reference#hash instead of Indexable#hash.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic_included_module_mro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/mro.cr" <<'CR'
module MM
  def foo(x)
    "MM"
  end
end

class Base0
  def foo
    foo(1)
  end
end

class Base1 < Base0
  def foo(x)
    "Base1"
  end
end

class Sub(T) < Base1
  include MM
end

class Sub2 < Base1
  include MM
end

STDERR.puts "generic=#{Sub(Int32).new.foo}"
STDERR.puts "plain=#{Sub2.new.foo}"
a = [{"a", "b"}]
b = [{"a", "b"}]
STDERR.puts "array_hash=#{a.hash == b.hash}"
h = {} of Array(String) => Int32
h[["a"]] = 1
h[["a"]] = 2
STDERR.puts "array_key_size=#{h.size}"
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/mro.cr" -o "$WORK_DIR/mro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/mro" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
for want in "generic=MM" "plain=MM" "array_hash=true" "array_key_size=1"; do
  if ! grep -qx "$want" "$WORK_DIR/run.log"; then
    echo "FAIL: missing '$want'" >&2
    cat "$WORK_DIR/run.log" >&2
    exit 1
  fi
done
echo generic_included_module_mro_repro_ok
