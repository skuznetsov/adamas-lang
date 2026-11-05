#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-macro-begin.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > "$work/main.cr" <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

def emit
  {% if false %}
    {% begin %}
      LibC.putchar(88)
    {% end %}
  {% else %}
    {% begin %}
      {% for code in [65, 66] %}
        LibC.putchar({{code}})
      {% end %}
    {% end %}
    LibC.putchar(67)
  {% end %}
end

emit
CR

compile() {
  local log="$1"
  shift
  if ! "$@" > "$log" 2>&1; then
    cat "$log" >&2
    exit 1
  fi
}

compile "$work/original.log" "$safe" "$original" 60 4096 build "$work/main.cr" \
  --prelude=empty --single-module --no-debug "${original_flags[@]}" -o "$work/original"
compile "$work/candidate.log" "$safe" "$candidate" 60 4096 "$work/main.cr" \
  --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$work/candidate"
"$safe" "$work/original" 5 512 > "$work/original.out"
"$safe" "$work/candidate" 5 512 > "$work/candidate.out"
printf ABC | diff -u - "$work/original.out"
diff -u "$work/original.out" "$work/candidate.out"
printf 'PASS nested macro begin, skipped branch, and trailing statement\n'
