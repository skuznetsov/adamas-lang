#!/usr/bin/env bash
# Regression: a quoted string literal whose content starts with `%` and a
# percent delimiter (`"%d|%x\n"`, `"%(ab)"`, `"%w[a b]"`).
#
# The parser decided whether a string token was a percent literal from the
# token's decoded content, so a quoted literal that merely starts with `%(`,
# `%|`, `%w[` ... was reparsed as one: `"%d|%x\n"` became `"%x"` (printf
# formats printed garbage) and `"%w[a b]"` failed to compile. Only a token
# the lexer scanned from a source `%` is a percent literal; real percent
# literals stay covered by the control case.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-quoted_percent_literal.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > quoted_printf_format.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end

s = "%d|%x\n"
LibC.exit(bs(s) &* 10 &+ (at(s, 2) == 124 ? 1 : 0))
CR

cat > quoted_paren_content.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end

s = "%(ab)"
LibC.exit(bs(s) &* 10 &+ (at(s, 1) == 40 ? 1 : 0))
CR

cat > quoted_word_array_content.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end

s = "%w[a b]"
LibC.exit(bs(s) &* 10 &+ (at(s, 2) == 91 ? 1 : 0))
CR

cat > quoted_pipe_then_escape.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end

s = "%d|\n"
LibC.exit(bs(s) &* 10 &+ (at(s, 3) == 10 ? 1 : 0))
CR

cat > real_percent_literals_control.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end

s = %(ab)
t = %|a b|
LibC.exit(bs(s) &* 10 &+ bs(t))
CR

cat > quoted_default_arg_and_percent_q.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end

def fmt(s : String = "%|x|") : Int32
  bs(s)
end
LibC.exit(fmt &* 10 &+ bs(%q(a|b)))
CR

exit_code() {
  local out
  out="$("$safe" "$1" 5 256 2>&1 || true)"
  printf '%s\n' "$out" | sed -n 's/^\[EXIT: \([0-9-]*\)\].*/\1/p' | tail -1
}

fail=0
check() {
  local case_name="$1" want="$2" got_original got_candidate
  "$safe" "$original" 120 4096 build "$case_name.cr" --prelude=empty --single-module \
    --no-debug "${original_flags[@]}" -o "$case_name.original" > "$case_name.original.log" 2>&1 ||
    { cat "$case_name.original.log" >&2; echo "ORACLE_BUILD_FAIL $case_name"; fail=1; return; }
  got_original="$(exit_code "$work/$case_name.original")"
  if [[ "$got_original" != "$want" ]]; then
    echo "ORACLE_MISMATCH $case_name: original=$got_original expected=$want"; fail=1; return
  fi
  if ! "$safe" "$candidate" 120 4096 "$case_name.cr" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$case_name.candidate" > "$case_name.candidate.log" 2>&1; then
    echo "FAIL $case_name: candidate compile failed"
    grep -a -m3 -i error "$case_name.candidate.log" || true
    fail=1; return
  fi
  got_candidate="$(exit_code "$work/$case_name.candidate")"
  if [[ "$got_candidate" != "$want" ]]; then
    echo "FAIL $case_name: candidate=$got_candidate expected=$want"; fail=1; return
  fi
  echo "ok $case_name"
}

check quoted_printf_format 61
check quoted_paren_content 51
check quoted_word_array_content 71
check quoted_pipe_then_escape 41
check real_percent_literals_control 23
check quoted_default_arg_and_percent_q 43

[[ $fail == 0 ]] || exit 1
printf 'PASS quoted_percent_literal\n'
