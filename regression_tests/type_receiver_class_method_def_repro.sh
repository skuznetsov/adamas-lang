#!/usr/bin/env bash
# `def Type.m` inside `struct Type` is a class method (Crystal resolves a Path
# def receiver to the type's metaclass). Only `def self.m` was recognized, so
# stdlib `def Float64.new(value)` became an instance method and
# `Float64.new(5_u64)` bound to `self.new(value : String, ...)` -> segfault.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/type_receiver_class_method.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class String
end
struct Foo
  def self.new(value : String, whitespace : Bool = true, strict : Bool = true) : Int32
    11
  end
  def Foo.new(value) : Int32
    22
  end
  def Foo.inbody(v) : Int32
    3
  end
  def ::Foo.rooted(v) : Int32
    5
  end
end
def Foo.toplevel(v) : Int32
  4
end
# 1000*22 + 3*100 + 5*10 + 4 = 22354; exits 0 only when every def bound right.
# (Foo.new stays the RHS: a user `new` returning non-self as a binary-op
# receiver is a separate open bug.)
r = 1000 &* Foo.new(7_u64) &+ Foo.inbody(1) &* 100 &+ Foo.rooted(1) &* 10 &+ Foo.toplevel(1)
LibC.exit(r &- 22354)
CR
cat >"$WORK_DIR/pr.cr" <<'CR'
a = Float64.new(5_u64)
b = "2.5".to_f
exit(a == 5.0 && b == 2.5 ? 0 : 1)
CR
for t in np pr; do
  flags=()
  [[ $t == np ]] && flags=(--no-prelude)
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 "$WORK_DIR/$t.cr" "${flags[@]}" -o "$WORK_DIR/$t" >"$WORK_DIR/build_$t.log" 2>&1 || { tail -5 "$WORK_DIR/build_$t.log" >&2; exit 1; }
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$t" 5 512 >"$WORK_DIR/run_$t.log" 2>&1 || { echo "FAIL: $t"; cat "$WORK_DIR/run_$t.log" >&2; exit 1; }
done
echo type_receiver_class_method_def_repro_ok
