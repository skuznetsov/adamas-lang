#!/usr/bin/env bash
# Regression: heredoc bodies must decode like Crystal's.
#
# The lexer copied a heredoc body verbatim: every line kept its indentation
# (only the closing delimiter's indentation is removed in Crystal), the line
# break before the closing delimiter stayed in the string, escapes such as
# `\t` were not decoded, `\` + newline was not a continuation, and an
# interpolated body became a plain string. `<<-'T'` raw bodies keep
# backslashes verbatim. CRLF bodies are covered by
# spec/parser/parser_heredoc_spec.cr.
#
# Usage: $0 [path/to/adamas]; ORIGINAL_CRYSTAL_BIN selects the oracle.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-heredoc_decode.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > escape_decoded.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end
s = <<-T
  a\tb
  T
LibC.exit(bs(s) &* 10 &+ (at(s, 1) == 9 ? 1 : 0))
CR

cat > dedent_keeps_extra_indent_and_blank_line.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end
s = <<-T
    a
  b

  T
LibC.exit(bs(s) &* 10 &+ (at(s, 0) == 32 ? 1 : 0) &+ (at(s, 5) == 10 ? 2 : 0))
CR

cat > raw_body_keeps_backslash.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end
s = <<-'T'
  a\tb
  T
LibC.exit(bs(s) &* 10 &+ (at(s, 1) == 92 ? 1 : 0))
CR

cat > empty_and_unindented_bodies.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end
s = <<-T
  T
t = <<-T
abc
T
LibC.exit(bs(s) &* 10 &+ bs(t))
CR

cat > two_heredocs_one_opener_line.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end
def f(a : String, b : String) : Int32
  bs(a) &* 10 &+ bs(b)
end
LibC.exit(f(<<-A, <<-B))
  xy
  A
    pqr
    B
CR

cat > percent_text_in_body.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end

s = <<-TEXT
  %(ab)
  TEXT
LibC.exit(bs(s) &* 10 &+ (at(s, 0) == 37 ? 1 : 0))
CR

cat > plain_body.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end
s = <<-TEXT
  abcde
  TEXT
LibC.exit(bs(s) &* 10 &+ (at(s, 0) == 97 ? 1 : 0))
CR

cat > newline_escape_before_final_break.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end
s = <<-T
  a\n
  T
LibC.exit(bs(s) &* 10 &+ (at(s, 1) == 10 ? 1 : 0))
CR

cat > backslash_newline_continuation.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end
s = <<-T
  a \
    b
  T
LibC.exit(bs(s) &* 10 &+ (at(s, 2) == 98 ? 1 : 0))
CR

cat > whitespace_only_line.cr <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def bs(s : String) : Int32
  (s.as(UInt8*) + 4).as(Int32*).value
end

def at(s : String, i : Int32) : Int32
  (s.as(UInt8*) + 12 + i).value.to_i32!
end
s = <<-T
  a
 
  b
  T
LibC.exit(bs(s) &* 10 &+ (at(s, 2) == 10 ? 1 : 0))
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

check escape_decoded 31
check dedent_keeps_extra_indent_and_blank_line 63
check raw_body_keeps_backslash 41
check empty_and_unindented_bodies 3
check two_heredocs_one_opener_line 23
check percent_text_in_body 51
check plain_body 51
check newline_escape_before_final_break 21
check backslash_newline_continuation 31
check whitespace_only_line 41

[[ $fail == 0 ]] || exit 1
printf 'PASS heredoc_decode\n'
