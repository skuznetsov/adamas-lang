#!/usr/bin/env bash
# Tuple coercion reads struct pointer carriers, even for 64-byte values.
# Ordinary parent fields retain their inline layout. Both small-struct ABI
# settings must preserve the tuple contract and nullable branch payloads.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/tuple-struct-carrier.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct WideToken
  @a : Int64
  @b : Int64
  @c : Int64
  @d : Int64
  @e : Int64
  @f : Int64
  @g : Int64
  @h : Int64
  def initialize(@a : Int64, @b : Int64, @c : Int64, @d : Int64, @e : Int64, @f : Int64, @g : Int64, @h : Int64)
  end
  def first : Int64
    @a
  end
  def last : Int64
    @h
  end
end
def pair(flag : Bool) : Tuple(Int32?, WideToken?)
  if flag
    {17, WideToken.new(11_i64, 22_i64, 33_i64, 44_i64, 55_i64, 66_i64, 77_i64, 88_i64)}
  else
    {nil, nil}
  end
end
a, b = pair(true)
LibC.exit(11) unless a == 17
LibC.exit(12) unless b
if b
  LibC.exit(13) unless b.first == 11
  LibC.exit(14) unless b.last == 88
end
a, b = pair(false)
LibC.exit(15) unless a.nil?
LibC.exit(16) unless b.nil?
class Holder
  @token : WideToken
  def initialize(@token : WideToken)
  end
  def token : WideToken
    @token
  end
end
holder = Holder.new(WideToken.new(11_i64, 22_i64, 33_i64, 44_i64, 55_i64, 66_i64, 77_i64, 88_i64))
LibC.exit(17) unless holder.token.first == 11
LibC.exit(18) unless holder.token.last == 88
# Repeat after the Nil branch and an ordinary inline parent-field read.
a, b = pair(true)
LibC.exit(19) unless b && b.last == 88
LibC.exit(0)
CR
for gate in 0 1; do
  if ! ADAMAS_INLINE_SMALL_STRUCTS="$gate" "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/repro.cr" --no-prelude -o "$work/repro-$gate" > "$work/compile-$gate.log" 2>&1; then
    cat "$work/compile-$gate.log"
    exit 1
  fi
  if ! "$root/scripts/run_safe.sh" "$work/repro-$gate" 5 512 > "$work/run-$gate.log" 2>&1; then
    cat "$work/run-$gate.log"
    exit 1
  fi
  echo "PASS[inline_small_structs=$gate]: wide tuple carriers, Nil, repeat and inline parent"
done
