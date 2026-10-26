#!/usr/bin/env bash
# Union dispatch maps a Char or Bool arm of `to_s` to the receiver-only
# intrinsics __adamas_char_to_string/__adamas_bool_to_string. The mapping
# ignored the call's arguments, so `obj.to_s io` on a `Char | ...` union
# became a call of the intrinsic with an extra argument, and prelude hello
# failed with "undefined method '__adamas_char_to_string'" at io.cr
# `def <<(obj : _)`. Only the zero-argument form is the intrinsic. Positive
# cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union-to-s-io.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  cat > "$WORK_DIR/$name.cr" <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Sink
  def initialize
    @n = 0
  end

  def n : Int32
    @n
  end

  def add(x : Int32) : Nil
    @n = @n &+ x
  end

  def <<(obj) : self
    obj.to_s self
    self
  end
end

struct Char
  def to_s(io : Sink) : Nil
    io.add(40)
  end
end

HEAD
  printf '%s\n' "$body" >> "$WORK_DIR/$name.cr"
}

write_case char_int_arm 'struct Int32
  def to_s(io : Sink) : Nil
    io.add(2)
  end
end

def pick(i : Int32) : Char | Int32
  i == 0 ? '"'"'a'"'"' : 1
end

s = Sink.new
s << pick(0)
s << pick(1)
LibC.exit(s.n)'
write_case char_bool_arm 'struct Bool
  def to_s(io : Sink) : Nil
    io.add(2)
  end
end

def pick(i : Int32) : Char | Bool
  i == 0 ? '"'"'a'"'"' : true
end

s = Sink.new
s << pick(1)
s << pick(0)
LibC.exit(s.n)'

POSITIVE=(char_int_arm char_bool_arm)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${POSITIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run exit %s)\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
