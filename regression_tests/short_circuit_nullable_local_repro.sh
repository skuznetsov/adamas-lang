#!/usr/bin/env bash
# A narrowing inside a skipped short-circuit RHS must not replace the local
# value reaching the join. Keep executed RHS assignments observable as well.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/short_circuit_nullable.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
cat > "$TMP_DIR/probe.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Choice
  getter value : Int32
  def initialize(@value : Int32)
  end
end
def choose_or(first : Choice?, label : String?) : Int32
  selected = first || nil
  name = label || (selected ? "present" : nil)
  unless selected
    selected = Choice.new(99)
  end
  selected.value
end
def choose_and(first : Choice?, label : String?) : Int32
  selected = first || nil
  name = label && (selected ? "present" : nil)
  unless selected
    selected = Choice.new(99)
  end
  selected.value
end
def assign_or(first : Choice?, label : String?) : Int32
  selected = first
  name = label || begin
    selected = Choice.new(42)
    "assigned"
  end
  selected ? selected.value : 99
end
def assign_and(first : Choice?, label : String?) : Int32
  selected = first
  name = label && begin
    selected = Choice.new(42)
    "assigned"
  end
  selected ? selected.value : 99
end
LibC.exit(71) unless choose_or(Choice.new(7), "known") == 7
LibC.exit(72) unless choose_or(Choice.new(7), nil) == 7
LibC.exit(73) unless choose_or(nil, "known") == 99
LibC.exit(74) unless choose_or(nil, nil) == 99
LibC.exit(75) unless choose_and(Choice.new(7), nil) == 7
LibC.exit(76) unless choose_and(Choice.new(7), "known") == 7
LibC.exit(77) unless choose_and(nil, nil) == 99
LibC.exit(78) unless choose_and(nil, "known") == 99
LibC.exit(79) unless assign_or(Choice.new(7), "known") == 7
LibC.exit(80) unless assign_or(Choice.new(7), nil) == 42
LibC.exit(81) unless assign_or(nil, "known") == 99
LibC.exit(82) unless assign_and(Choice.new(7), nil) == 7
LibC.exit(83) unless assign_and(Choice.new(7), "known") == 42
LibC.exit(84) unless assign_and(nil, nil) == 99
LibC.exit(0)
CR
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
  "$TMP_DIR/probe.cr" --no-prelude -o "$TMP_DIR/probe"
"$ROOT_DIR/scripts/run_safe.sh" "$TMP_DIR/probe" 5 512
echo 'short_circuit_nullable_local_ok cases=14'
