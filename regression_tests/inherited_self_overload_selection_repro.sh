#!/usr/bin/env bash
# An untyped `def eqx(other)` and a restricted `def eqx(other : self)` defined
# in a parent (abstract class, abstract struct, or stdlib Enum) and called on a
# child: the parent-typed param only matched by subclass, which params_match_score
# did not reward, so both overloads tied and registration order picked the
# untyped one. Stdlib Enum defines `==(other)` (false) before `==(other : self)`,
# so `Tuple(Int32, SomeEnum)#==` was always false and stage2's final-missing
# convergence guard (a snapshot containing enum tuples) never converged.
# Second layer: a lazily lowered inherited method is registered under the child
# owner (`SK#eqx$String` aliasing the untyped parent def); that alias then
# became the child's only method-index candidate and hid the parent's
# `eqx(other : self)` overload for the later `SK#eqx$SK` request.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inherited_self_overload.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

abstract class Base
  def eqx(other) : Int32
    1
  end

  def eqx(other : self) : Int32
    2
  end
end

class K < Base
end

class L < Base
  def eqx(other : L) : Int32
    3
  end
end

abstract struct SBase
  def eqx(other) : Int32
    1
  end

  def eqx(other : self) : Int32
    2
  end
end

struct SK < SBase
end

def cmp(t : K, u : K) : Int32
  t.eqx(u)
end

LibC.exit(1) unless cmp(K.new, K.new) == 2
LibC.exit(2) unless K.new.eqx(7) == 1
LibC.exit(3) unless L.new.eqx(L.new) == 3
LibC.exit(4) unless SK.new.eqx(SK.new) == 2
LibC.exit(5) unless SK.new.eqx(7) == 1
LibC.exit(0)
CR
cat >"$WORK_DIR/pl.cr" <<'CR'
enum St
  A
  B
end

abstract struct SBase
  def eqx(other) : Int32
    1
  end

  def eqx(other : self) : Int32
    2
  end
end

struct SK < SBase
end

def cmp(t : {Int32, St}, u : {Int32, St}) : Bool
  t == u
end

a = [] of {Int32, St}
a << {1, St::B}
exit 1 unless cmp(a[0], a[0])
exit 3 unless St::B == St::B
exit 4 unless SK.new.eqx(SK.new) == 2
exit 5 unless SK.new.eqx("x") == 1
exit 0
CR
for name in np pl; do
  flags=()
  [[ "$name" == np ]] && flags=(--no-prelude)
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
      "$WORK_DIR/$name.cr" ${flags[@]+"${flags[@]}"} -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1; then
    echo "case $name failed:" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo inherited_self_overload_selection_repro_ok
