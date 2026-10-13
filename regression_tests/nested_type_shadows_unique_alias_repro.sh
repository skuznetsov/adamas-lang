#!/usr/bin/env bash
# A unique alias suffix (`Sys::Handler`) must not capture a bare `Handler`
# written inside a namespace that declares its own nested `Handler` type.
#
# resolve_contextual_alias_key vetoes the alias when the current class has a
# nested type of that name, but the unique-suffix fallback in
# resolve_contextual_type_alias_name / resolve_type_alias_by_suffix ignored
# the veto. In the self-host this retyped OptionParser's
# `Hash(String, Handler)` as `Hash(String, Crystal::System::Signal::Handler)`
# and S3 failed on a `Hash::Entry(String, Proc) | Hash::Entry(String,
# OptionParser::Handler)` receiver union.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested-type-alias-shadow.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

HEADER='lib LibC
  fun exit(code : Int32) : NoReturn
end

class Box(K, V)
  def initialize(@k : K, @v : V)
  end

  def v : V
    @v
  end
end

module Sys
  alias Handler = Int32

  @@handlers = Box(Int32, Handler).new(1, 11)

  def self.run : Int32
    @@handlers.v
  end
end
'

# name|expected exit code|body
cases=(
"same_class|81|
class Parser
  struct Handler
    def initialize(@n : Int32)
    end

    def n : Int32
      @n
    end
  end

  def initialize
    @handlers = Box(Int32, Handler).new(2, Handler.new(7))
  end

  def run : Int32
    @handlers.v.n
  end
end

LibC.exit(Sys.run + Parser.new.run * 10)"
"enclosing_namespace|61|
module Outer
  struct Handler
    def initialize(@n : Int32)
    end

    def n : Int32
      @n
    end
  end

  class Inner
    def make : Handler
      Handler.new(5)
    end
  end
end

LibC.exit(Sys.run + Outer::Inner.new.make.n * 10)"
)

failed=0
echo "compiler: $COMPILER"
for entry in "${cases[@]}"; do
  name="${entry%%|*}"
  rest="${entry#*|}"
  expected="${rest%%|*}"
  body="${rest#*|}"
  src="$TMP_DIR/$name.cr"
  out="$TMP_DIR/$name"
  printf '%s\n%s\n' "$HEADER" "$body" >"$src"

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 --no-prelude "$src" -o "$out" \
    >"$TMP_DIR/$name.compile.log" 2>&1
  compile_rc=$?
  set -e
  if [[ $compile_rc -ne 0 || ! -x "$out" ]]; then
    tail -40 "$TMP_DIR/$name.compile.log" >&2 || true
    echo "FAIL[$name]: compile rc=$compile_rc" >&2
    failed=1
    continue
  fi

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$out" 5 512 >"$TMP_DIR/$name.run.log" 2>&1
  set -e
  actual="$(grep -o 'EXIT: [0-9]*' "$TMP_DIR/$name.run.log" | head -1 | awk '{print $2}')"
  if [[ "$actual" != "$expected" ]]; then
    cat "$TMP_DIR/$name.run.log" >&2
    echo "FAIL[$name]: exit ${actual:-?}, expected $expected" >&2
    failed=1
  else
    echo "ok[$name]: exit $actual"
  fi
done

if [[ $failed -ne 0 ]]; then
  exit 1
fi
echo "PASS: nested types shadow unique alias suffixes"
