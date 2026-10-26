#!/usr/bin/env bash
# A class-restricted parameter keeps one shared body (`emit$Int32_Sink`), so
# `io.sync?` lowers to a virtual call on the restriction. Final HIR validation
# only accepted a source family on the restriction and its ancestors, so a
# method declared by a subclass (directly or through an included module) was
# reported as "undefined method 'sync?' for Sink". The 1.22.1 prelude hits
# this in Crystal.print_buffered (`io.sync?` on `to io : IO`, defined only in
# IO::Buffered). A virtual call reaches descendant bodies, so a descendant
# declaration is source authority, but only while every concrete type that
# callers pass into the parameter responds: a subclass lacking the method is
# rejected like in Crystal. A method no descendant declares is rejected too.
# Each positive case exits 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/virtual-descendant-method.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/includer_module_named_splat.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

abstract class Sink
  abstract def put(x : Int32) : Int32
end

module Buf
  def sync? : Bool
    false
  end
end

class FdSink < Sink
  include Buf

  def put(x : Int32) : Int32
    x + 40
  end
end

class MemSink < Sink
  def put(x : Int32) : Int32
    x
  end
end

module Out
  def self.emit(msg : Int32, *args, to io : Sink, extra = nil) : Int32
    r = io.put(msg)
    r = r + 0 unless io.sync?
    r
  end
end

ERR = FdSink.new
MemSink.new.put(0)
LibC.exit(Out.emit(2, to: ERR))
CR

cat > "$WORK_DIR/direct_subclass_def.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

abstract class Sink
  abstract def put(x : Int32) : Int32
end

module Buf
  def sync? : Bool
    false
  end
end

class FdSink < Sink
  def sync? : Bool
    false
  end

  def put(x : Int32) : Int32
    x + 40
  end
end

class MemSink < Sink
  def put(x : Int32) : Int32
    x
  end
end

module Out
  def self.emit(msg : Int32, io : Sink) : Int32
    r = io.put(msg)
    r = r + 0 unless io.sync?
    r
  end
end

ERR = FdSink.new
MemSink.new.put(0)
LibC.exit(Out.emit(2, ERR))
CR

cat > "$WORK_DIR/concrete_parent.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

class Sink
  def put(x : Int32) : Int32
    0
  end
end

module Buf
  def sync? : Bool
    false
  end
end

class FdSink < Sink
  include Buf

  def put(x : Int32) : Int32
    x + 40
  end
end

class MemSink < Sink
  def put(x : Int32) : Int32
    x
  end
end

module Out
  def self.emit(msg : Int32, io : Sink) : Int32
    r = io.put(msg)
    r = r + 0 unless io.sync?
    r
  end
end

ERR = FdSink.new
MemSink.new.put(0)
LibC.exit(Out.emit(2, ERR))
CR

cat > "$WORK_DIR/no_descendant_declares.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

abstract class Sink
  abstract def put(x : Int32) : Int32
end

module Buf
  def sync? : Bool
    false
  end
end

class FdSink < Sink
  include Buf

  def put(x : Int32) : Int32
    x + 40
  end
end

class MemSink < Sink
  def put(x : Int32) : Int32
    x
  end
end

module Out
  def self.emit(msg : Int32, *args, to io : Sink, extra = nil) : Int32
    r = io.put(msg)
    r = r + 0 unless io.nope?
    r
  end
end

ERR = FdSink.new
MemSink.new.put(0)
LibC.exit(Out.emit(2, to: ERR))
CR

cat > "$WORK_DIR/forwarded_param.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

abstract class Sink
  abstract def put(x : Int32) : Int32
end

class FdSink < Sink
  def sync? : Bool
    false
  end

  def put(x : Int32) : Int32
    42
  end
end

class MemSink < Sink
  def put(x : Int32) : Int32
    x
  end
end


def emit(io : Sink) : Int32
  io.sync?
  io.put(1)
end

def outer(io : Sink) : Int32
  emit(io)
end

MemSink.new.put(0)
LibC.exit(outer(FdSink.new))
CR

cat > "$WORK_DIR/includer_other_subclass_rejected.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

abstract class Sink
  abstract def put(x : Int32) : Int32
end

module Buf
  def sync? : Bool
    false
  end
end

class FdSink < Sink
  include Buf

  def put(x : Int32) : Int32
    x + 40
  end
end

class MemSink < Sink
  def put(x : Int32) : Int32
    x
  end
end

module Out
  def self.emit(msg : Int32, *args, to io : Sink, extra = nil) : Int32
    r = io.put(msg)
    r = r + 0 unless io.sync?
    r
  end
end

ERR = FdSink.new
MemSink.new.put(0)
LibC.exit(Out.emit(2, to: MemSink.new))
CR

cat > "$WORK_DIR/forwarded_other_subclass_rejected.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

abstract class Sink
  abstract def put(x : Int32) : Int32
end

class FdSink < Sink
  def sync? : Bool
    false
  end

  def put(x : Int32) : Int32
    42
  end
end

class MemSink < Sink
  def put(x : Int32) : Int32
    x
  end
end


def emit(io : Sink) : Int32
  io.sync?
  io.put(1)
end

def outer(io : Sink) : Int32
  emit(io)
end

MemSink.new.put(0)
LibC.exit(outer(MemSink.new))
CR

cat > "$WORK_DIR/virtual_inflow_rejected.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

abstract class Sink
  abstract def put(x : Int32) : Int32
end

class FdSink < Sink
  def sync? : Bool
    false
  end

  def put(x : Int32) : Int32
    42
  end
end

class MemSink < Sink
  def put(x : Int32) : Int32
    x
  end
end


def emit(io : Sink) : Int32
  io.sync?
  io.put(1)
end

def pick(i : Int32) : Sink
  i == 1 ? FdSink.new : MemSink.new
end

LibC.exit(emit(pick(1)))
CR

cat > "$WORK_DIR/merged_forwarded_params.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

abstract class Sink
  abstract def put(x : Int32) : Int32
end

class FdSink < Sink
  def sync? : Bool
    false
  end

  def put(x : Int32) : Int32
    42
  end
end

class MemSink < Sink
  def put(x : Int32) : Int32
    x
  end
end


def emit(io : Sink) : Int32
  io.sync?
  io.put(1)
end

def outer(a : Sink, b : Sink, i : Int32) : Int32
  emit(i == 1 ? a : b)
end

MemSink.new.put(0)
LibC.exit(outer(FdSink.new, FdSink.new, 1))
CR

cat > "$WORK_DIR/merged_other_subclass_rejected.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

abstract class Sink
  abstract def put(x : Int32) : Int32
end

class FdSink < Sink
  def sync? : Bool
    false
  end

  def put(x : Int32) : Int32
    42
  end
end

class MemSink < Sink
  def put(x : Int32) : Int32
    x
  end
end


def emit(io : Sink) : Int32
  io.sync?
  io.put(1)
end

def outer(a : Sink, b : Sink, i : Int32) : Int32
  emit(i == 1 ? a : b)
end

MemSink.new.put(0)
LibC.exit(outer(FdSink.new, MemSink.new, 1))
CR

CASES=(
  "includer_module_named_splat:42"
  "direct_subclass_def:42"
  "concrete_parent:42"
  "forwarded_param:42"
  "merged_forwarded_params:42"
)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
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
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
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
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

# Both compilers must reject these: no descendant declares `nope?`, or a
# subclass without `sync?` reaches the parameter (directly, through a
# forwarding parameter, or as a value of the abstract restriction type).
REJECTS=(
  "no_descendant_declares:nope?"
  "includer_other_subclass_rejected:sync?"
  "forwarded_other_subclass_rejected:sync?"
  "virtual_inflow_rejected:sync?"
  "merged_other_subclass_rejected:sync?"
)
for entry in "${REJECTS[@]}"; do
  reject_name="${entry%%:*}"
  method="${entry#*:}"
  if [[ -n "$CRYSTAL_BIN" ]]; then
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$reject_name.cr" -o "$WORK_DIR/$reject_name.orig" > "$WORK_DIR/$reject_name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$reject_name" >&2
      exit 2
    fi
  fi
  reject_log="$WORK_DIR/$reject_name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$reject_name.cr" \
    -o "$WORK_DIR/$reject_name.adamas" > "$reject_log" 2>&1 || true
  if grep -q "undefined method '$method'" "$reject_log" && [[ ! -e "$WORK_DIR/$reject_name.adamas" ]]; then
    printf 'PASS %s (rejected)\n' "$reject_name"
  else
    printf 'FAIL %s: expected undefined method %s diagnostic\n' "$reject_name" "$method"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d virtual descendant method case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'virtual descendant method cases passed\n'
