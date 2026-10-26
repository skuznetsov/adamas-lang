#!/usr/bin/env bash
# A call that passes only named arguments to a def with a positional splat
# (`file.each_line(chomp: chomp)` to `IO#each_line(*args, **options, &)`)
# must bind the splat to the empty Tuple. Named-argument reordering filled
# the unreached splat slot with its Nil placeholder, so the forwarded
# `gets(*args, **options)` saw a Nil positional: stage 2 failed in
# File.read_lines with "no overload matches IO#gets for argument types
# (Nil, Bool) and named arguments chomp". An unknown named argument must stay
# rejected. Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-only-empty-splat.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  {
    cat <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def kind(x : Nil)
  1
end

def kind(x)
  40
end

class Io
  def gets(chomp = true) : Int32
    chomp ? 30 : 40
  end

  def gets(limit : Int32, chomp = true) : Int32
    limit &+ (chomp ? 1 : 2)
  end

  def each_line(*args, **options, &)
    yield gets(*args, **options)
  end
end

class Reader
  def self.read(chomp = true)
    total = 0
    Io.new.each_line(chomp: chomp) do |line|
      total = line
    end
    total
  end
end

def splat_then_named(*args, flag = false)
  kind(args) &+ (flag ? 2 : 0)
end

def splat_and_options(*args, **options)
  kind(args) &+ 2
end

HEAD
    printf '%s\n' "$body"
  } > "$WORK_DIR/$name.cr"
}

write_case yield_forward_in_method "LibC.exit(Reader.read(false) &+ 2)"
write_case yield_forward_top_level "Io.new.each_line(chomp: false) { |x| LibC.exit(x &+ 2) }
LibC.exit(1)"
write_case yield_forward_positional "Io.new.each_line(10, chomp: false) { |x| LibC.exit(x &+ 30) }
LibC.exit(1)"
write_case splat_then_named_param "LibC.exit(splat_then_named(flag: true))"
write_case splat_and_double_splat "LibC.exit(splat_and_options(x: 1))"
# Negative: no gets overload takes `foo`. (Adamas currently reports this
# through the receiver-repair "bodyless target" diagnostic.)
write_case unknown_named_rejected "Io.new.each_line(foo: 1) { |x| LibC.exit(x) }
LibC.exit(1)"

POSITIVE=(yield_forward_in_method yield_forward_top_level yield_forward_positional splat_then_named_param
  splat_and_double_splat)
NEGATIVE=(unknown_named_rejected)

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
  for name in "${NEGATIVE[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
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
    printf 'FAIL %s (run): exit %s, expected 42\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]] && grep -q "no overload matches\|left bodyless target" "$log"; then
    printf 'PASS %s (rejected)\n' "$name"
  else
    printf 'FAIL %s: expected an overload error\n' "$name"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d named-only empty splat case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Named-only empty splat cases passed\n'
