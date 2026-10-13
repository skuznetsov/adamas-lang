#!/usr/bin/env bash
# A type literal calling a Class meta-instance method that takes arguments
# (`Abcde.show(io)` resolving to `Class#show$Sink`) was rewritten by swapping
# the owner separator into a receiverless `Class.show$Sink`: the literal owner
# was dropped and the call bound to a never-lowered stub. The call must go
# through the per-type literal wrapper so `Abcde` stays the receiver.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/type_literal_meta_method.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_meta.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

abstract class Sink
  abstract def put(s : String) : Nil
end

class Cnt < Sink
  @n = 0

  def put(s : String) : Nil
    @n += 1
  end

  def n
    @n
  end
end

class Class
  def show(io : Sink) : Nil
    io.put({{ @type.name.stringify }})
  end

  def show2(io : Sink) : Nil
    show(io)
  end
end

class Abcde
end

def q(o, io)
  o.show2(io)
end

c = Cnt.new
Abcde.show(c)
q(Abcde, c)
LibC.exit(c.n == 2 ? 0 : 1)
CR
for name in np_meta; do
  flags=()
  [[ "$name" == np_* ]] && flags=(--no-prelude)
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
echo type_literal_meta_method_args_repro_ok
