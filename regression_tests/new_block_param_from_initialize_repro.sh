#!/usr/bin/env bash
# `K.new { |x| ... }` on a class without its own `self.new` goes through the
# allocator, which has no source def. block_param_types_for_call then fell
# into the builder-constructor shortcut (`Hash.new { |h, k| }` yields the
# receiver) and typed `x` as `K`, so `x == 5` became Reference#== and the
# stored block always returned false. The block signature must come from
# `#initialize(&blk : Int32 -> Bool)` (also for a generic owner `G(T)` and
# an inherited initializer).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/new_block_param_from_initialize_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
class K
  def initialize(&blk : Int32 -> Bool)
    @blk = blk
  end

  def go(x)
    @blk.call(x)
  end
end

class K2 < K
end

class G(T)
  def initialize(&blk : T -> Bool)
    @blk = blk
  end

  def go(x : T)
    @blk.call(x)
  end
end

k = K.new { |x| x == 5 }
STDERR.puts "k1=#{k.go(5)}"
STDERR.puts "k2=#{k.go(4)}"
k2 = K2.new { |x| x > 10 }
STDERR.puts "s1=#{k2.go(11)}"
STDERR.puts "s2=#{k2.go(3)}"
g = G(String).new { |s| s.size == 3 }
STDERR.puts "g1=#{g.go("abc")}"
STDERR.puts "g2=#{g.go("ab")}"
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
k1=true
k2=false
s1=true
s2=false
g1=true
g2=false
OUT
grep -oE '^[a-z_0-9]+=(true|false)' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: allocator block param was typed as the receiver class" >&2
  exit 1
fi
echo "PASS: allocator block param typed from #initialize"
