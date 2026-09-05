#!/usr/bin/env bash
# Macro-generated yields must retain the accumulator and every element type
# when the block is materialized as a proc. An unrelated same-name method must
# never become the receiver's call target.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
CASE="${2:-accumulator}"
case "$CASE" in
  accumulator|--class-union) ;;
  *) echo "Usage: $0 [compiler] [--class-union]" >&2; exit 2 ;;
esac
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_macro_yield.XXXXXX")" || exit 2
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT
cat > "$TMP_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Enumerable(T)
end
struct Tuple
  include Enumerable(Union(*T))
  def reduce(memo, &)
    {% for i in 0...T.size %}
      memo = yield memo, self[{{ i }}]
    {% end %}
    memo
  end
end
class Path
  def initialize(@value : Int32)
  end
  def value : Int32
    @value
  end
  def join(part : Int32) : Path
    Path.new(@value &+ part)
  end
  def join(parts : Tuple(Int32, Int32)) : Path
    parts.reduce(self) { |path, part| path.join(part) }
  end
end
class Thread
  def join : Nil
    nil
  end
end
Thread.new.join
result = Path.new(39).join({1, 2})
LibC.exit(result.value &- 42)
CR

# The union control needs a nonempty OtherPart: an empty alternative can hide
# a wrong overload. Its sentinel also exposes a lost callback return value.
if [[ "$CASE" == "--class-union" ]]; then
  cat > "$TMP_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Enumerable(T)
end
struct Tuple
  include Enumerable(Union(*T))
  def reduce(memo, &)
    {% for i in 0...T.size %}
      memo = yield memo, self[{{ i }}]
    {% end %}
    memo
  end
end
class Path
  def initialize(@value : Int32)
  end
  def value : Int32
    @value
  end
  def join(part : Path) : Path
    Path.new(@value &+ part.value)
  end
  def join(part : OtherPart) : Path
    self
  end
  def join(parts : Tuple(Path | OtherPart, Path | OtherPart)) : Path
    parts.reduce(self) { |path, part| path.join(part) }
  end
end
class OtherPart
  def initialize(@sentinel : Int32 = 100)
  end
end
class Thread
  def join : Nil
    nil
  end
end
Thread.new.join
def parts : Tuple(Path | OtherPart, Path | OtherPart)
  {Path.new(1), Path.new(2)}
end
result = Path.new(39).join(parts)
LibC.exit(11) unless result.value == 42

def other_parts : Tuple(Path | OtherPart, Path | OtherPart)
  {OtherPart.new, Path.new(3)}
end
other_result = Path.new(39).join(other_parts)
LibC.exit(other_result.value &- 42)
CR
fi

ADAMAS_DISABLE_INLINE_YIELD=1 "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 1024 \
  "$TMP_DIR/repro.cr" --no-prelude -o "$TMP_DIR/repro" > "$TMP_DIR/compile.log" 2>&1
compile_rc=$?
if [[ "$compile_rc" -ne 0 ]]; then
  cat "$TMP_DIR/compile.log"
  exit 1
fi
if [[ ! -x "$TMP_DIR/repro" ]]; then
  echo "FAIL: compiler produced no executable"
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$TMP_DIR/repro" 5 512 > "$TMP_DIR/runtime.log" 2>&1
runtime_rc=$?
if [[ "$runtime_rc" -ne 0 ]]; then
  cat "$TMP_DIR/runtime.log"
  exit 1
fi
if [[ "$CASE" == "--class-union" ]]; then
  echo "PASS: macro yield class-union alternatives select their own overloads"
else
  echo "PASS: macro yield proc retains accumulator and element types"
fi
