#!/usr/bin/env bash
# Oracle for the "inline-yield + next" trap (Path#each_parent brk family,
# s2_v11 parallel-emission killer).
#
# Shape: a block passed to an inlined yielding method (`Reader#each`, a while
# loop) contains BOTH a non-local `return tuple` and a `next`. Blocks with
# `next` are normally NOT inlined (proc fallback), but a non-local return
# forces inlining. inline_block_body pushed a yield-continuation block onto
# @loop_cond_stack so `next` jumps to post-yield code, but the wiring guard
# `unless ctx.get_block(ctx.current_block).terminator` was always false
# (terminator defaults to an Unreachable placeholder), so the continuation
# stayed an orphan Unreachable block and every executed `next` hit a trap
# (SIGTRAP brk #0x1), e.g. Path#next_part_separator_index inside
# Dir.mkdir_p -> Path#each_parent.
#
# RED (pre-fix): binary traps with no output (exit 133).
# GREEN: three parts printed, clean exit. The main loop is bounded to 3
# iterations so the still-open zero-iteration loop-exit-phi sibling (start_pos
# reads garbage when the inlined loop runs 0 times) does not affect this
# oracle.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yield_next_nonlocal.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
cat > "$SRC" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

struct Reader
  @pos : Int32
  @len : Int32

  def initialize(@pos : Int32, @len : Int32)
  end

  def pos
    @pos
  end

  def has_next?
    @pos < @len
  end

  def current
    @pos
  end

  def each(&) : Nil
    while has_next?
      yield current
      @pos += 1
    end
  end
end

def next_part(reader : Reader, last_was_separator : Bool) : Tuple(Reader, Bool, Int32)?
  start_pos = reader.pos

  reader.each do |v|
    if v == 2 || v == 5
      if last_was_separator
        next
      end

      return reader, true, start_pos
    elsif last_was_separator
      start_pos = reader.pos
      last_was_separator = false
    end
  end

  unless last_was_separator
    {reader, false, start_pos}
  end
end

reader = Reader.new(0, 8)
last = false
count = 0
while count < 3 && (nxt = next_part(reader, last))
  reader, last, start_pos = nxt
  LibC.printf("part pos=%d last=%d start=%d\n", reader.pos, last ? 1 : 0, start_pos)
  count += 1
end
LibC.printf("done count=%d\n", count)
CR

if ! "$COMPILER" "$SRC" --no-prelude -o "$OUT" > "$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile error" >&2
  tail -5 "$TMP_DIR/compile.log" >&2
  exit 1
fi

RAW="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null)"
GOT="$(echo "$RAW" | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
EXPECTED=$'part pos=2 last=1 start=0\npart pos=5 last=1 start=3\npart pos=8 last=0 start=6\ndone count=3'

if [[ "$GOT" != "$EXPECTED" ]]; then
  echo "FAIL: output mismatch" >&2
  echo "--- expected ---" >&2
  echo "$EXPECTED" >&2
  echo "--- got ---" >&2
  echo "$GOT" >&2
  exit 1
fi
if ! echo "$RAW" | grep -q "\[EXIT: 0\]"; then
  echo "FAIL: non-zero exit (trap on the next path?)" >&2
  echo "$RAW" | tail -2 >&2
  exit 1
fi
echo "PASS: next inside force-inlined yield block reaches the continuation"
