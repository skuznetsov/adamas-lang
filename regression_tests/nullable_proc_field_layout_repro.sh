#!/usr/bin/env bash
# Exercise class re-registration with equivalent nullable tuple key spellings.
# The full prelude is required: Hash's self-typed default callback exposes the
# early arrow-Proc layout path. ASan detects the write even if empty? succeeds.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/nullable-proc-field.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cat > "$work/repro.cr" <<'CR'
a = Hash(Tuple(UInt64, UInt64, String?), Nil).new(initial_capacity: 0)
b = Hash(Tuple(UInt64, UInt64, Nil | String), Nil).new(initial_capacity: 0)
exit 11 unless a.empty? && b.empty?
c = Hash(String, Nil).new(initial_capacity: 0)
exit 12 unless c.empty?
CR
run_logged() {
  local log="$1"
  shift
  if ! "$@" > "$work/$log" 2>&1; then
    cat "$work/$log"
    return 1
  fi
}
run_logged compile.log "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/repro.cr" -o "$work/repro"
python3 - "$work/repro.ll" "$work/asan.ll" <<'PY'
import re, sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
source, count = re.subn(r'^(define .*?)\s*\{', r'\1 sanitize_address {', source, flags=re.M)
assert count, 'No LLVM functions were instrumented'
Path(sys.argv[2]).write_text(source)
PY
clang_bin="${CLANG:-clang}"
link_flags=(-lgc -lpcre2-8 -lpcre)
if [[ "$(uname -s)" == Darwin ]]; then
  if [[ -z "${CLANG:-}" && -x /opt/homebrew/opt/llvm/bin/clang ]]; then
    clang_bin=/opt/homebrew/opt/llvm/bin/clang
  fi
  link_flags+=(-L/opt/homebrew/opt/bdw-gc/lib -L/opt/homebrew/opt/pcre2/lib -L/opt/homebrew/opt/pcre/lib -liconv -Wl,-stack_size,0x4000000)
fi
run_logged asan-build.log "$root/scripts/run_safe.sh" "$clang_bin" 90 8192 -O0 -fsanitize=address "$work/asan.ll" "${link_flags[@]}" -o "$work/asan"
run_logged asan-run.log env ASAN_OPTIONS=detect_leaks=0 "$root/scripts/run_safe.sh" "$work/asan" 10 1024
printf '%s\n' 'PASS: nullable Proc fields fit Hash objects for both tuple-key spellings and String control'
