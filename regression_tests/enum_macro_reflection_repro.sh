#!/usr/bin/env bash
# Enum metadata must reach HIR macro conditions, loops and constant lookup.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/enum-macro-reflection.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/reflection.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Enum
  def flag_value : Int32
    {% if @type.annotation(Flags) %}
      11
    {% else %}
      22
    {% end %}
  end
  def member_label : String?
    {% for member in @type.constants %}
      if self.value == {{@type.constant(member)}}
        return {{member.stringify}}
      end
    {% end %}
  end
end
@[Flags]
enum Bits
  Read
  Write
end
enum Plain
  Zero
  Seven = 7
end
def plain : Plain
  Plain::Seven
end
def bits : Bits
  Bits::Write
end
LibC.exit(11) unless plain.flag_value == 22
LibC.exit(12) unless bits.flag_value == 11
LibC.exit(13) unless plain.member_label == "Seven"
LibC.exit(14) unless bits.member_label == "Write"
LibC.exit(0)
CR
cat > "$work/names.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Left
  enum Kind
    Zero
    Seven = 7
    Alias = 7
  end
end
module Right
  enum Kind
    OtherZero
    OtherSeven = 7
  end
end
def left_zero : Left::Kind
  Left::Kind::Zero
end
def left_alias : Left::Kind
  Left::Kind::Alias
end
def right_seven : Right::Kind
  Right::Kind::OtherSeven
end
def unknown : Left::Kind
  Left::Kind.new(91)
end
LibC.exit(11) unless left_zero.to_s == "Zero"
LibC.exit(12) unless left_alias.to_s == "Seven"
LibC.exit(13) unless right_seven.to_s == "OtherSeven"
LibC.exit(14) unless unknown.to_s == "91"
LibC.exit(15) unless left_alias.to_s == "Seven"
LibC.exit(0)
CR
for name in reflection names; do
  flags=()
  if [[ "$name" == reflection ]]; then flags+=(--no-prelude); fi
  if ! "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/$name.cr" "${flags[@]}" -o "$work/$name" > "$work/$name.log" 2>&1; then
    cat "$work/$name.log"
    exit 1
  fi
  if ! "$root/scripts/run_safe.sh" "$work/$name" 5 512 >> "$work/$name.log" 2>&1; then
    cat "$work/$name.log"
    exit 1
  fi
  echo "PASS[$name]"
done
