#!/usr/bin/env bash
# Local-type body inference must honor (1) self-referential ternaries
# (`x = x == V ? y : merge(x, y)` reads x's pre-assignment view) and
# (2) guard narrowing (`next unless y` makes a later `x = y` non-nil).
# Without these, `mark(x)` was typed `mark$Nil | TR` and S2 failed with an
# ambiguous mark_runtime_type_identity call (or a STUB CALLED at runtime).
# Soundness guards: a reassignment after the guard, or a loop back edge that
# re-enters after a later reassignment, must end the non-nil narrowing.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/local_infer_guard_and_ternary_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/t.cr" <<'CR'
struct TR
  VOID = new(0)
  getter v : Int32
  def initialize(@v : Int32); end
  def ==(other : TR) : Bool
    @v == other.v
  end
end

class A
  def inf(x : Int32) : TR?
    x > 0 ? TR.new(x) : nil
  end

  def un(a : TR, b : TR) : TR
    TR.new(a.v + b.v)
  end

  # The defaulted param routes the call through body-level local-type
  # inference (infer_arg_types_for_call); plain calls do not reach it.
  private def mark(t : TR, d : String? = nil) : Nil
    STDERR.puts "#{d}=#{t.v}"
  end

  def ternary(args : Array(Int32))
    acc = TR::VOID
    args.each do |arg_id|
      arg_type = inf(arg_id)
      next unless arg_type
      next if arg_type == TR::VOID
      acc = acc == TR::VOID ? arg_type : un(acc, arg_type)
    end
    mark(acc, "ternary")
  end

  def next_unless(args : Array(Int32))
    last = TR::VOID
    args.each do |arg_id|
      arg_type = inf(arg_id)
      next unless arg_type
      last = arg_type
    end
    mark(last, "next_unless")
  end

  def next_if_nil(args : Array(Int32))
    last = TR::VOID
    args.each do |arg_id|
      arg_type = inf(arg_id)
      next if arg_type.nil?
      last = arg_type
    end
    mark(last, "next_if_nil")
  end

  def break_unless(args : Array(Int32))
    last = TR::VOID
    args.each do |arg_id|
      arg_type = inf(arg_id)
      break unless arg_type
      last = arg_type
    end
    mark(last, "break_unless")
  end

  def return_unless(arg_id : Int32)
    last = TR::VOID
    arg_type = inf(arg_id)
    return unless arg_type
    last = arg_type
    mark(last, "return_unless")
  end

  def and_guard(args : Array(Int32))
    last = TR::VOID
    args.each do |arg_id|
      a = inf(arg_id)
      b = inf(arg_id + 1)
      next unless a && b
      last = un(a, b)
      last = b
    end
    mark(last, "and_guard")
  end

  private def kind(t : TR) : String
    "TR#{t.v}"
  end

  private def kind(t : Nil) : String
    "nil"
  end

  private def probe(t, d : String? = nil)
    STDERR.puts "#{d}=#{kind(t)}"
  end

  def reassign_after_guard(args : Array(Int32))
    last = TR::VOID
    args.each do |arg_id|
      x = inf(arg_id)
      next unless x
      x = inf(-arg_id)
      last = x
    end
    probe(last, "reassign_after_guard")
  end

  def back_edge(args : Array(Int32))
    x = inf(1)
    return unless x
    last = TR::VOID
    args.each do |arg_id|
      last = x
      x = inf(arg_id)
    end
    probe(last, "back_edge")
  end
end

A.new.ternary([1, -1, 2])
A.new.next_unless([1, -1, 2])
A.new.next_if_nil([3, -1, -2])
A.new.break_unless([4, -1, 5])
A.new.return_unless(-1)
A.new.return_unless(6)
A.new.and_guard([7, -3])
A.new.reassign_after_guard([1])
A.new.back_edge([-1, 5])
STDERR.flush
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/t.cr" -o "$WORK_DIR/t" --emit hir >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

if grep -F 'mark$Nil' "$WORK_DIR"/t.hir >&2; then
  echo "FAIL: guarded/ternary local inferred as nilable" >&2
  exit 1
fi
if grep -F 'probe$TR_' "$WORK_DIR"/t.hir >&2; then
  echo "FAIL: reassigned/back-edge local unsoundly narrowed to non-nil" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/t" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
cat >"$WORK_DIR/expected" <<'OUT'
ternary=3
next_unless=2
next_if_nil=3
break_unless=4
return_unless=6
and_guard=8
reassign_after_guard=nil
back_edge=nil
OUT
grep -E '^[a-z_]+=' "$WORK_DIR/run.log" >"$WORK_DIR/actual" || true
if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/actual" >&2; then
  echo "FAIL: local inference ignores guard narrowing / ternary self-reference" >&2
  exit 1
fi
echo "PASS: local inference honors guard narrowing and ternary self-reference"
