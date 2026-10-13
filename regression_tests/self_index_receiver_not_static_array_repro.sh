#!/usr/bin/env bash
# `self[i].m(x)` (e.g. Tuple#hash: `hasher = self[{{i}}].hash(hasher)`) was
# classified as a type-like receiver: `self` counts as type-like and an
# IndexNode over a type is StaticArray sugar, so the call was lowered as the
# class call `StaticArray(Owner, i).m(x)` -> abort stub (S2 died on every
# Hash({UInt64, Symbol}, _) key_hash). `self[...]` is always an index call.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/self_index_receiver.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_self_index.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

struct Int32
  def foo(h : Int32) : Int32
    h &+ self
  end
end

struct Pair(T)
  def initialize(@a : T, @b : T)
  end

  def [](i : Int32) : T
    i == 0 ? @a : @b
  end

  def mix(h : Int32) : Int32
    {% for i in 0...2 %}
      h = self[{{i}}].foo(h)
    {% end %}
    h
  end

  def self.[](i : Int32) : Int32
    i &* 100
  end

  def self.cmix(h : Int32) : Int32
    self[2].foo(h)
  end
end

p = Pair(Int32).new(3, 4)
LibC.exit(p.mix(10) == 17 && Pair(Int32).cmix(5) == 205 ? 3 : 1)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/np_self_index.cr" --no-prelude -o "$WORK_DIR/np_self_index" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/np_self_index" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/run.log"; then
  echo "case np_self_index failed:" >&2
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo self_index_receiver_not_static_array_repro_ok
