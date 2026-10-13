#!/usr/bin/env bash
# Named receiver repair must find the source overload in produced compilers.
# A positional call with the named-only default is the non-repair control.
set -u -o pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:?usage: $0 COMPILER}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named_receiver_shape.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
fail=0
compile_run() {
  local name=$1 expected=$2
  shift 2
  local src="$TMP_DIR/$name.cr" out="$TMP_DIR/$name" log="$TMP_DIR/$name.log"
  cat > "$src"
  "$RUN_SAFE" "$COMPILER" 60 4096 "$src" --no-prelude -o "$out" > "$log" 2>&1
  local c=$?
  if [[ $c -ne 0 || ! -x "$out" ]]; then
    echo "FAIL[$name]: compile rc=$c"
    cat "$log"
    fail=1
    return
  fi
  "$RUN_SAFE" "$out" 5 512 >> "$log" 2>&1
  local r=$?
  if [[ $r -ne "$expected" ]]; then
    echo "FAIL[$name]: runtime rc=$r expected=$expected"
    cat "$log"
    fail=1
  else
    echo "PASS[$name] rc=$r"
  fi
}
compile_run compatible 0 <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
enum Kind
  A
  B
end
struct Probe
  def to_kind(kind, *, mappings : Bool = true) : Int32
    kind == Kind::B ? (mappings ? 42 : 73) : -1
  end
  def check : Int32
    to_kind(Kind::B, mappings: false)
  end
end
LibC.exit(Probe.new.check == 73 ? 0 : 21)
CR
compile_run positional 0 <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
enum Kind
  A
  B
end
struct Probe
  def to_kind(kind, *, mappings : Bool = true) : Int32
    kind == Kind::B ? (mappings ? 42 : 73) : -1
  end
end
LibC.exit(Probe.new.to_kind(Kind::B) == 42 ? 0 : 22)
CR
exit "$fail"
