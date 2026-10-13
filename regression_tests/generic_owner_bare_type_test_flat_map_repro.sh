#!/usr/bin/env bash
# Two bugs broke Array(Array(T))#flat_map (S2: bodyless insert_elements_at):
# A) inside a generic owner, `when Array` / type tests specialized the bare
#    `Array` to the owner's instantiation (Array(Array(Int32))), so the test
#    statically folded to false and flat_map pushed instead of concatenating;
# B) the transitive included-module owner set, meant for block-param inference,
#    also chose call targets and named the template `Enumerable(T)#...$block`.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic_owner_bare_type_test.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
module Enumerable(T)
  def case_kind(& : T -> _)
    r = 0
    each do |e|
      case v = yield e
      when Array, Iterator
        r += 1
      else
        r += 100
      end
    end
    r
  end

  def is_a_kind(& : T -> _)
    r = 0
    each do |e|
      v = yield e
      r += v.is_a?(Array) ? 1 : 100
    end
    r
  end
end

hs = [[40], [1]]
exit 1 unless hs.case_kind { |x| x } == 2
exit 2 unless hs.is_a_kind { |x| x } == 2
t = 0
hs.flat_map { |x| x }.each { |p| t += p }
exit 3 unless t == 41
exit 0
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
    "$WORK_DIR/repro.cr" -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  grep -E '^\[EXIT' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo generic_owner_bare_type_test_flat_map_repro_ok
