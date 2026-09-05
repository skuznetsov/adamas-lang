#!/usr/bin/env bash
# Same runtime argument types must not merge allocators selecting different
# positional and named-only initializer bodies. Exercise both discovery orders.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/allocator_named_shape.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
failures=0
run_case() {
  local name="$1"
  cat > "$TMP_DIR/$name.cr"
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
      "$TMP_DIR/$name.cr" --no-prelude -o "$TMP_DIR/$name" > "$TMP_DIR/$name.compile.log" 2>&1; then
    echo "FAIL[$name]: compile"
    cat "$TMP_DIR/$name.compile.log"
    failures=$((failures + 1))
  elif ! "$ROOT_DIR/scripts/run_safe.sh" "$TMP_DIR/$name" 5 512 > "$TMP_DIR/$name.run.log" 2>&1; then
    echo "FAIL[$name]: runtime"
    cat "$TMP_DIR/$name.run.log"
    failures=$((failures + 1))
  else
    echo "PASS[$name]"
  fi
}
for order in named_first positional_first; do
  run_case "$order" < <(
    cat <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct ReaderShape
  getter pos : Int32
  def initialize(value : String, pos = 0)
    @pos = pos
  end
  def initialize(*, at_end value : String)
    @pos = 99
  end
end
CR
    if [[ "$order" == named_first ]]; then
      echo 'named = ReaderShape.new(at_end: "count")'
      echo 'positional = ReaderShape.new("count")'
    else
      echo 'positional = ReaderShape.new("count")'
      echo 'named = ReaderShape.new(at_end: "count")'
    fi
    cat <<'CR'
LibC.exit(71) unless positional.pos == 0
LibC.exit(72) unless named.pos == 99
LibC.exit(73) unless ReaderShape.new("count", 7).pos == 7
LibC.exit(0)
CR
  )
done
run_case generic_shapes <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Shape(T)
  getter marker : Int32
  def initialize(value : T)
    @marker = 7
  end
  def initialize(*, special value : T)
    @marker = 99
  end
end
named = Shape(Int32).new(special: 42)
positional = Shape(Int32).new(42)
LibC.exit(74) unless named.marker == 99
LibC.exit(75) unless positional.marker == 7
LibC.exit(0)
CR
run_case named_positional_parameter <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Ordinary
  getter marker : Int32
  def initialize(@marker : Int32)
  end
end
LibC.exit(Ordinary.new(marker: 73).marker - 73)
CR
run_case named_only_constructor <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class NamedOnly
  getter marker : Int32
  def initialize(*, value : Int32)
    @marker = value
  end
end
LibC.exit(NamedOnly.new(value: 73).marker - 73)
CR
run_case distinct_named_only_bodies <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class MultiNamed
  getter marker : Int32
  def initialize(*, first value : Int32)
    @marker = 11
  end
  def initialize(*, second value : Int32)
    @marker = 22
  end
end
first = MultiNamed.new(first: 1)
second = MultiNamed.new(second: 2)
LibC.exit(76) unless first.marker == 11
LibC.exit(77) unless second.marker == 22
LibC.exit(0)
CR
run_case explicit_new_authority <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class ExplicitShape
  def initialize(*, special value : Int32)
  end
  def self.new(value : Int32) : Int32
    LibC.exit(value - 41)
  end
end
ExplicitShape.new(41)
LibC.exit(79)
CR
run_case named_defaults <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class MixedNamed
  getter marker : Int32
  def initialize(value : Int32, *, flag : Int32 = 7)
    @marker = value + flag
  end
end
a = MixedNamed.new(value: 1)
b = MixedNamed.new(value: 1, flag: 2)
LibC.exit(80) unless a.marker == 8
LibC.exit(1) unless b.marker == 3
class MultiDefault
  getter marker : Int32
  def initialize(*, first value : Int32 = 11)
    @marker = value
  end
  def initialize(*, second value : Int32 = 22)
    @marker = value
  end
end
c = MultiDefault.new(first: 3)
d = MultiDefault.new(second: 4)
LibC.exit(2) unless c.marker == 3
LibC.exit(3) unless d.marker == 4
LibC.exit(0)
CR
if (( failures > 0 )); then
  echo "FAIL: $failures allocator shape cases"
  exit 1
fi
