#!/usr/bin/env bash
# `p == Kind::First` with `p : Kind? = nil` in its Nil specialization lowered to a raw
# BinaryOp comparing the nil pointer (0) with the enum payload, so `nil == Kind::First`
# (value 0) was true. In the bootstrap this made `parameter_provenance ==
# ParameterSliceProvenance::SourceBacked` true for a nil provenance, so stage2 read
# parameter type annotations from foreign source spans. The `Nil | Kind` specialization
# had the same bug: the enum coerce cast the whole union to Int32 (payload 0 == First).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nil_enum_equality_fold_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Foo
  enum Kind
    First
    Second
  end
  def eq_default(p : Kind? = nil) : Bool
    p == Kind::First
  end
  def ne_default(p : Kind? = nil) : Bool
    p != Kind::First
  end
  def eq_reversed(p : Kind? = nil) : Bool
    Kind::First == p
  end
  def eq_call(p : Kind? = nil) : Bool
    p.==(Kind::First)
  end
  def eq_nilable(p : Kind?) : Bool
    p == Kind::First
  end
end
foo = Foo.new
LibC.exit(1) if foo.eq_default
LibC.exit(2) unless foo.ne_default
LibC.exit(3) if foo.eq_reversed
LibC.exit(4) if foo.eq_call
LibC.exit(5) if foo.eq_nilable(nil)
LibC.exit(6) unless foo.eq_nilable(Foo::Kind::First)
LibC.exit(7) if foo.eq_default(Foo::Kind::Second)
LibC.exit(8) unless foo.ne_default(Foo::Kind::Second)
LibC.exit(9) unless 3 != nil
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo nil_enum_equality_fold_repro_ok
