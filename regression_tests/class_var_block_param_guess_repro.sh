#!/usr/bin/env bash
# A class var assigned from a parameter of the enclosing def is guessed as
# original Crystal does: from the restriction, else the default, else an
# unrestricted `&block` is a `-> Void` proc. The guess was missing, so a read
# lowered before the assignment saw Void and silently skipped the call, while
# an assignment lowered first fixed the slot to bare `Proc` ("cannot call
# Proc#call without a concrete Proc signature"; stdlib GC.before_collect
# stores its block this way). A call with arguments must still be rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/class-var-block-param-guess.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Proc boxes are heap-allocated, so no-prelude fixtures link libgc.
PRELUDE='@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end

class Object
  def try(&)
    yield self
  end
end

struct Nil
  def try(&)
    self
  end
end
'

write_case() {
  printf '%s\n%s\n' "$PRELUDE" "$2" > "$WORK_DIR/$1.cr"
}

write_case read_before_assignment '
module G
  @@n = 0

  def self.n
    @@n
  end

  def self.bump
    @@n = 7
  end

  def self.run
    @@c.try(&.call)
  end

  def self.before(&block) : Nil
    @@c = block
  end
end

G.before { G.bump; nil }
G.run
LibC.exit(G.n)'

write_case assignment_before_read '
module G
  @@n = 0

  def self.n
    @@n
  end

  def self.bump
    @@n = 6
  end

  def self.before(&block) : Nil
    @@c = block
  end

  def self.run
    @@c.try(&.call)
  end
end

G.before { G.bump; nil }
G.run
LibC.exit(G.n)'

write_case typed_param_guess '
module G
  def self.get
    @@v
  end

  def self.set(x : Int32)
    @@v = x
  end
end

G.set(5)
v = G.get
LibC.exit(v ? v : 1)'

write_case block_guess_rejects_argument '
module G
  def self.before(&block) : Nil
    @@c = block
  end

  def self.run
    @@c.try(&.call(1))
  end
end

G.before { nil }
G.run'

POSITIVE_CASES=(read_before_assignment:7 assignment_before_read:6 typed_param_guess:5)
NEGATIVE_CASES=("block_guess_rejects_argument:#call'")

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${POSITIVE_CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
  for entry in "${NEGATIVE_CASES[@]}"; do
    name="${entry%%:*}"
    diagnostic="${entry#*:}"
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1 ||
        ! grep -qF "$diagnostic" "$WORK_DIR/$name.orig.log"; then
      printf 'ORACLE FAIL: original does not reject %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${POSITIVE_CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL positive %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS positive %s\n' "$name"
  else
    printf 'FAIL positive %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

for entry in "${NEGATIVE_CASES[@]}"; do
  name="${entry%%:*}"
  diagnostic="${entry#*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "1" ]] && grep -qF "$diagnostic" "$log" &&
      [[ ! -e "$WORK_DIR/$name.adamas" ]]; then
    printf 'PASS negative %s\n' "$name"
  else
    printf 'FAIL negative %s (exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d class-var block-parameter guess case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'class-var block-parameter guess cases passed\n'
