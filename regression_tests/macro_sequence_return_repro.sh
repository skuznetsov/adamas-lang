#!/usr/bin/env bash
# Parsed macro expansions must stop at a return, just like ordinary source bodies.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:-$root/bin/adamas}"
baseline="${2:-}"
work="$(mktemp -d "${TMPDIR:-/tmp}/macro-sequence-return.XXXXXX")"
trap 'if [[ "${KEEP_TMP:-0}" == 1 ]]; then echo "kept_tmp=$work"; else rm -rf "$work"; fi' EXIT
cat > "$work/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def first_expansion : Int32
  {% for n in [17, 23] %}
    return {{n}}
  {% end %}
  99
end

def conditional_expansion(minimum : Int32) : Int32
  {% for n in [17, 23] %}
    return {{n}} if {{n}} > minimum
  {% end %}
  99
end

def both_return(flag : Bool) : Int32
  {% for n in [17, 23] %}
    if flag
      return {{n}}
    else
      return {{n}} + 100
    end
  {% end %}
  99
end

ok = first_expansion == 17 && conditional_expansion(0) == 17 &&
  conditional_expansion(20) == 23 && conditional_expansion(30) == 99 &&
  both_return(true) == 17 && both_return(false) == 117
LibC.exit(ok ? 0 : 91)
CR
compile() {
  "$root/scripts/run_safe.sh" "$1" 120 8192 "$work/repro.cr" --no-prelude -o "$work/$2" > "$work/$2-compile.log" 2>&1 || {
    cat "$work/$2-compile.log" >&2; return 1;
  }
}
compile "$compiler" candidate
"$root/scripts/run_safe.sh" "$work/candidate" 5 512 > "$work/candidate-run.log" 2>&1 || {
  cat "$work/candidate-run.log" >&2; exit 1;
}
if [[ -n "$baseline" ]]; then
  compile "$baseline" baseline
  status=0
  "$root/scripts/run_safe.sh" "$work/baseline" 5 512 > "$work/baseline-run.log" 2>&1 || status=$?
  if [[ "$status" != 91 ]]; then
    echo "FAIL: expected baseline semantic failure 91, got $status" >&2
    cat "$work/baseline-run.log" >&2
    exit 1
  fi
fi
echo "PASS: macro returns preserve first return, conditional fallthrough, and dead merges"
