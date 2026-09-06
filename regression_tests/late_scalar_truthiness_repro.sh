#!/usr/bin/env bash
# Late scalar MIR conditions follow Crystal truthiness, including numeric zero.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/late-scalar-truthiness.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/scalars.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
n = 0
f = 0.0
LibC.exit(11) unless n
LibC.exit(12) unless f
LibC.exit(13) if false
LibC.exit(14) if nil
LibC.exit(15) unless true

def choose(index : Int32) : Int32 | Bool | Nil
  return 0 if index == 0
  return false if index == 1
  nil
end
LibC.exit(16) unless choose(0)
LibC.exit(17) if choose(1)
LibC.exit(18) if choose(2)
LibC.exit(0)
CR
cat > "$work/comparable.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Domain
  record Potential, score : Int32 do
    include Comparable(Potential)
    def <=>(other : Potential)
      score <=> other.score
    end
  end
end
a = Domain::Potential.new(1)
b = Domain::Potential.new(2)
LibC.exit(21) unless a <= a
LibC.exit(22) unless a >= a
LibC.exit(23) unless a < b
LibC.exit(24) if b <= a
LibC.exit(25) if a >= b
LibC.exit(0)
CR
for name in scalars comparable; do
  flags=()
  if [[ "$name" == scalars ]]; then flags+=(--no-prelude); fi
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
