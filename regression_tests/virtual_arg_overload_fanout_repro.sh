#!/usr/bin/env bash
# A module method overloaded on subclasses (lit(IdN) / lit(NumN) / lit(TypedNode))
# called with an abstract-typed argument must fan out on the runtime class of
# the argument, including the nil-returning fallback overload.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/virtual_arg_overload_fanout_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
module Fe
  abstract class Node
    abstract def kind : Int32
  end
  abstract class TypedNode < Node
  end
  class IdN < TypedNode
    getter name : String
    def initialize(@name : String); end
    def kind : Int32; 1; end
  end
  class NumN < TypedNode
    getter v : String
    def initialize(@v : String); end
    def kind : Int32; 2; end
  end
  class OtherN < TypedNode
    def kind : Int32; 3; end
  end

  def self.lit(node : IdN) : String?
    node.name
  end
  def self.lit(node : NumN) : String?
    node.v
  end
  def self.lit(node : TypedNode) : String?
    nil
  end

  class Arena
    def initialize; @a = [] of TypedNode; end
    def add(n : TypedNode) : Int32
      @a << n
      @a.size - 1
    end
    def [](i : Int32) : TypedNode
      @a[i]
    end
  end
end

ar = Fe::Arena.new
i0 = ar.add(Fe::IdN.new("foo"))
i1 = ar.add(Fe::NumN.new("42"))
i2 = ar.add(Fe::OtherN.new)
[i0, i1, i2].each do |i|
  n = ar[i]
  r = Fe.lit(n)
  if r
    STDERR.puts "#{i} S=#{r}"
  else
    STDERR.puts "#{i} NIL"
  end
end
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
0 S=foo
1 S=42
2 NIL
OUT
grep -E '^[0-9] ' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: abstract argument fans out over module overloads" >&2
  exit 1
fi
echo "PASS: abstract argument fans out over module overloads"
