#!/usr/bin/env bash
# Regression: a class variable's declaration initializer is lowered lazily
# (once-guarded init function). It was called only before READS, so a write
# that happened before the first read was clobbered: `init` assigned
# `@@seen = 3`, then `@@seen + 4` ran the initializer (`@@seen = 0`) first and
# returned 4. Original Crystal runs the initializer at the declaration point,
# which precedes every later read and write. Each case must print EXIT 7.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/classvar_write_before_lazy_init.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

HEAD_SRC='lib LibC
  fun exit(status : Int32) : NoReturn
end
'

# module class var written by a class method before any read
cat >"$WORK_DIR/module_write.cr" <<CR
$HEAD_SRC
module M
  @@seen = 0

  def self.init : Nil
    @@seen = 3
  end

  def self.run : Int32
    init
    @@seen + 4
  end
end

LibC.exit(M.run)
CR

# class class var with a non-literal initializer, written then read
cat >"$WORK_DIR/class_write.cr" <<CR
$HEAD_SRC
class Reg
  @@count : Int32 = 10 - 10

  def self.bump(n : Int32) : Nil
    @@count = n
  end

  def self.count : Int32
    @@count
  end
end

Reg.bump(5)
LibC.exit(Reg.count + 2)
CR

# initializer still runs when the first access is a read
cat >"$WORK_DIR/read_first.cr" <<CR
$HEAD_SRC
class Cfg
  @@base = 3 + 4

  def self.base : Int32
    @@base
  end
end

LibC.exit(Cfg.base)
CR

for name in module_write class_write read_first; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    echo "case $name: compile failed" >&2
    tail -20 "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 7\]' "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT 7):" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo classvar_write_before_lazy_init_repro_ok
