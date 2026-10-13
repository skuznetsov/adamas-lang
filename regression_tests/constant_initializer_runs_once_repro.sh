#!/usr/bin/env bash
# A top-level `C = Mk.mk` was initialized twice: once by lower_main's deferred
# constant loop and again when the declaration itself was lowered as a main
# expression. Side effects in the initializer ran twice and the second object
# replaced the first. Original Crystal runs initialize_const once.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/constant_initializer_runs_once.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_top.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Cnt
  @n = 0
  def bump
    @n += 1
  end
  def n
    @n
  end
end

class Mk
  @@made = 0
  def self.made
    @@made
  end
  def self.mk
    @@made += 1
    Cnt.new
  end
end

C = Mk.mk

class Holder
  D = Mk.mk
end

C.bump
C.bump
Holder::D.bump
LibC.exit(Mk.made == 2 ? (C.n == 2 && Holder::D.n == 1 ? 3 : 20 + C.n) : 10 + Mk.made)
CR
check() {
  local name="$1" want="$2"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q "^\[EXIT: $want\]" "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT $want):" >&2
    cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
}
check np_top 3
echo constant_initializer_runs_once_repro_ok
