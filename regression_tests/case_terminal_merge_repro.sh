#!/usr/bin/env bash
# A case whose branches all exit has no implicit result or successor.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
safe="$root/scripts/run_safe.sh"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
work="$(mktemp -d "${TMPDIR:-/tmp}/case-terminal.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/returns.cr" <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

class Context
end

def condition(flag : Bool, context : Context) : {Bool, Context}
  case
  when flag
    LibC.putchar(65)
    return {true, context}
  else
    LibC.putchar(66)
    return {false, context}
  end
end

def nested(outer : Bool, inner : Bool) : Int32
  if outer
    case
    when inner
      return 67
    else
      return 68
    end
  else
    69
  end
end

class First
end

class Second
end

def exhaustive(value : First | Second) : Int32
  case value
  in First
    return 70
  in Second
    return 71
  end
end

context = Context.new
condition(true, context)
condition(false, context)
LibC.putchar(nested(true, true))
LibC.putchar(nested(true, false))
LibC.putchar(nested(false, false))
LibC.putchar(exhaustive(First.new))
LibC.putchar(exhaustive(Second.new))
LibC.putchar(10)
CR
printf 'ABCDEFG\n' > "$work/expected"

cat > "$work/reachable_fallthrough.cr" <<'CR'
def value(flag : Bool) : Int32
  case
  when flag
    return 1
  end
end

value(false)
CR

sed 's/return 67/return "wrong"/' "$work/returns.cr" > "$work/wrong_return.cr"

for mode in original lazy eager; do
  case "$mode" in
    original) build=("$safe" "$stock" 60 2048 build --prelude=empty "${link[@]}") ;;
    lazy) build=("$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
    eager) build=(env ADAMAS_EAGER_MONO=1 "$safe" "$candidate" 60 2048 --no-prelude --no-ast-cache --no-llvm-cache) ;;
  esac
  "${build[@]}" "$work/returns.cr" -o "$work/returns" > "$work/build.log" 2>&1 || { cat "$work/build.log" >&2; exit 1; }
  "$safe" "$work/returns" 5 512 > "$work/actual" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/expected" "$work/actual"
  for invalid in reachable_fallthrough wrong_return; do
    if "${build[@]}" "$work/$invalid.cr" -o "$work/invalid" > "$work/invalid.log" 2>&1; then
      echo "$mode accepted $invalid" >&2
      exit 1
    fi
    case "$invalid" in
      reachable_fallthrough) diagnostic='return .*Int32.*returning .*Nil' ;;
      wrong_return) diagnostic='return .*Int32.*returning .*String' ;;
    esac
    grep -E "$diagnostic" "$work/invalid.log" >/dev/null || { cat "$work/invalid.log" >&2; exit 1; }
  done
  echo "$mode matched the terminal case results and rejected both invalid returns"
done
