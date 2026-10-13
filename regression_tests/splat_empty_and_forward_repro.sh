#!/usr/bin/env bash
# Two splat-call defects:
# A) A bare zero-arg call (`put0` / `put0()`) to a top-level `def put0(*objects)`
#    was emitted without the empty Tuple() splat slot on the bare-identifier and
#    top-level bare-call paths, so the call targeted a name never lowered.
# B) lower_def counted the packed Tuple splat slot as a trailing positional, left
#    the splat slice empty and typed `*objects` as Tuple(); `put1 *objects`
#    then expanded to zero arguments.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/splat_empty_forward.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
write_cnt() {
  cat >"$WORK_DIR/$1.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Cnt
  @n = 0

  def put0 : Nil
    @n += 1
  end

  def put0(*objects : _) : Nil
    objects.each { |o| @n += 10 }
    @n += 100
  end

  def n
    @n
  end
end

C = Cnt.new

def put0(*objects) : Nil
  C.put0 *objects
end

def pq(o)
  put0
  o
end
CR
}
write_cnt np_bare_in_def
echo 'pq(5)
LibC.exit(C.n == 1 ? 3 : (C.n == 100 ? 4 : 1))' >>"$WORK_DIR/np_bare_in_def.cr"
write_cnt np_bare_top
echo 'put0
LibC.exit(C.n == 1 ? 3 : (C.n == 100 ? 4 : 1))' >>"$WORK_DIR/np_bare_top.cr"
write_cnt np_paren_top
echo 'put0()
LibC.exit(C.n == 1 ? 3 : (C.n == 100 ? 4 : 1))' >>"$WORK_DIR/np_paren_top.cr"
cat >"$WORK_DIR/np_forward.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def put1(x)
  x
end

def put0(*objects)
  put1 *objects
end

def put2(a, *rest)
  a + put1(*rest)
end

LibC.exit(put0(3) + put2(1, 3))
CR
cat >"$WORK_DIR/prelude_forward.cr" <<'CR'
def put1(x)
  x
end

def put0(*objects)
  put1 *objects
end

exit put0(7)
CR
check() {
  local name="$1" want="$2"; shift 2
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" "$@" -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
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
check np_bare_in_def 3 --no-prelude
check np_bare_top 3 --no-prelude
check np_paren_top 3 --no-prelude
check np_forward 7 --no-prelude
check prelude_forward 7
echo splat_empty_and_forward_repro_ok
