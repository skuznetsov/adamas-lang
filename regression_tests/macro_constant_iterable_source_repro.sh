#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-macro-constant-iterable.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
export CRYSTAL_PATH="$(env -u CRYSTAL_PATH "$original" env CRYSTAL_PATH)"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > collections.cr <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

CODES = {69, 70}
VALUES = [{65, 88}, {65, 89}]
MAPPED = {67 => 68}
NAMED = {first: 71}
RANGE = 72..73

class Report
  CODES = {74, 75}

  def self.emit
    {% for entry, index in VALUES %}
      LibC.putchar({{entry[0] + index}})
    {% end %}

    {% begin %}
      {% for key, value, index in MAPPED %}
        LibC.putchar({{key + index}})
        LibC.putchar({{value}})
      {% end %}
      {% for code in ::CODES %}
        LibC.putchar({{code}})
      {% end %}
      {% for key, value in NAMED %}
        {% if key.stringify == "first" %}
          LibC.putchar({{value}})
        {% end %}
      {% end %}
    {% end %}

    {% for code in RANGE %}
      LibC.putchar({{code}})
    {% end %}
    {% for code in CODES %}
      LibC.putchar({{code}})
    {% end %}
    {% for code in Report::CODES %}
      LibC.putchar({{code + 2}})
    {% end %}
  end
end

Report.emit
CR

cat > generated_stats.cr <<'CR'
class Report
  METRICS = {:opened, :closed}

  def write(left, right)
    stats = aggregate(left, right)
    puts stats[:opened]
    puts stats[:closed]
  end

  private def aggregate(left, right)
    {% for metric in METRICS %}
      {{metric.id}} = left[:{{metric.id}}] + right[:{{metric.id}}]
    {% end %}
    {% begin %}
      {
        {% for metric in METRICS %}
          {{metric.id}}: {{metric.id}},
        {% end %}
      }
    {% end %}
  end
end

Report.new.write({opened: 2_i64, closed: 3_i64}, {opened: 5_i64, closed: 7_i64})
CR

compile() {
  local log="$1"
  shift
  if ! "$@" > "$log" 2>&1; then
    cat "$log" >&2
    exit 1
  fi
}

check() {
  local name="$1"
  compile "$name.original.log" "$safe" "$original" 90 4096 build "$name.cr"     --single-module --no-debug "${original_flags[@]}" -o "$name.original"
  compile "$name.candidate.log" "$safe" "$candidate" 120 8192 "$name.cr"     --no-debug --no-ast-cache --no-llvm-cache -o "$name.candidate"
  "$safe" "$work/$name.original" 5 512 > "$name.original.out"
  "$safe" "$work/$name.candidate" 5 512 > "$name.candidate.out"
  diff -u "$name.original.out" "$name.candidate.out"
}

check collections
printf ABCDEFGHIJKLM | diff -u - collections.original.out
check generated_stats
printf '7\n10\n' | diff -u - generated_stats.original.out
printf 'PASS constant collection iteration, lexical binding, and generated NamedTuple\n'
