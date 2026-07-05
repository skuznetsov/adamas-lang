#!/usr/bin/env bash
# Oracle for the zero-iteration loop-exit value sibling (Path#each_parent
# wrong-parents / termination family).
#
# Shape: a var assigned inside an inlined yield-block loop is read AFTER the
# loop. lower_while registered the saved raw body value (latch value) as the
# post-loop local instead of the header phi, even when the header phi had
# received its backedge incoming. The latch value does not dominate the exit
# when the loop runs zero times, so the tail read garbage (start_pos=0
# instead of 8), breaking `break if reader.pos == start_pos` in
# Path#each_part_separator_index.
#
# RED (pre-fix): prints start=0. GREEN: start=8 (matches host Crystal).
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zero_iter_exit.XXXXXX")"
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

nxt = next_part(Reader.new(8, 8), false)
if nxt
  LibC.printf("tuple pos=%d last=%d start=%d\n", nxt[0].pos, nxt[1] ? 1 : 0, nxt[2])
else
  LibC.printf("nil\n")
end
CR

if ! "$COMPILER" "$SRC" --no-prelude -o "$OUT" > "$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile error" >&2
  tail -5 "$TMP_DIR/compile.log" >&2
  exit 1
fi

RAW="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null)"
GOT="$(echo "$RAW" | sed -n '/=== STDOUT ===/,/=== STDERR ===/p' | sed '1d;$d')"
EXPECTED="tuple pos=8 last=0 start=8"

if [[ "$GOT" != "$EXPECTED" ]]; then
  echo "FAIL: zero-iteration exit value mismatch" >&2
  echo "--- expected ---" >&2
  echo "$EXPECTED" >&2
  echo "--- got ---" >&2
  echo "$GOT" >&2
  exit 1
fi
echo "PASS: zero-iteration loop exit reads the header phi value"
