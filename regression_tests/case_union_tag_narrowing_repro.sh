#!/usr/bin/env bash
# A multi-condition case branch keeps precisely the admitted runtime carriers.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-case-union-tags.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cat >"$work/positive.cr" <<'CRYSTAL'
def exact_hash(value : Hash(String, Int32))
  10 + value.size
end

def hash_or_named(value)
  case value
  when Hash, NamedTuple
    exact_hash(value)
  else
    20
  end
end

def typed_value(value : Hash(String, Int32))
  30 + value.size
end

def typed_value(value : NamedTuple(code: Int32))
  value[:code]
end

def hash_and_named(value)
  case value
  when Hash, NamedTuple
    typed_value(value)
  else
    50
  end
end

hash = if ARGV[0] == "hash"
         {"one" => 1}
       elsif ARGV[0] == "other"
         3_i64
       else
         2_i64
       end
three = if ARGV[0] == "hash"
          {"one" => 1}
        elsif ARGV[0] == "tuple"
          {code: 40}
        else
          2_i64
        end
puts hash_or_named(hash)
puts hash_and_named(three)

def mixed_pattern_value(value : Hash(String, Int32))
  60 + value.size
end

def mixed_pattern_value(value : Int64)
  70
end

def type_and_value_pattern(value)
  case value
  when Hash, 2_i64
    mixed_pattern_value(value)
  else
    80
  end
end

puts type_and_value_pattern(hash)
CRYSTAL

cat >"$work/negative.cr" <<'CRYSTAL'
def exact_hash(value : Hash(String, Int32))
  value.size
end

def visit(value)
  case value
  when Hash, NamedTuple
    exact_hash(value)
  else
    0
  end
end

value = ARGV[0] == "hash" ? {"one" => 1} : {code: 40}
puts visit(value)
CRYSTAL

compile() {
  local mode="$1" input="$2" output="$3"
  if [[ "$mode" == original ]]; then
    "$safe" "$original" 90 4096 build "$input" --no-debug "${stock_link[@]}" -o "$output"
  else
    env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO \
      "$safe" "$candidate" 90 4096 "$input" --no-debug --no-ast-cache --no-llvm-cache -o "$output"
  fi
}

for mode in original candidate; do
  if ! compile "$mode" "$work/positive.cr" "$work/program" >"$work/compile.log" 2>&1; then
    tail -40 "$work/compile.log" >&2
    exit 1
  fi
  for sample in 'hash:11 31 61' 'tuple:20 40 70' 'scalar:20 50 70' 'other:20 50 80'; do
    "$safe" "$work/program" 5 512 "${sample%:*}" >"$work/stdout"
    read -r -a expected <<<"${sample#*:}"
    printf '%s\n' "${expected[@]}" >"$work/expected"
    diff -u "$work/expected" "$work/stdout"
  done

  code=0
  compile "$mode" "$work/negative.cr" "$work/rejected" >"$work/rejected.log" 2>&1 || code=$?
  if [[ "$code" != 1 ]] || ! rg -q 'no overload matches.*exact_hash|expected argument.*Hash' "$work/rejected.log"; then
    tail -40 "$work/rejected.log" >&2
    exit 1
  fi
  printf 'PASS case union tags (%s)\n' "$mode"
done
