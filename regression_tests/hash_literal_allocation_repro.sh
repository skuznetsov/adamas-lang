#!/usr/bin/env bash
# No-prelude layout probe: a Hash body wider than the old fixed allocation,
# with the empty-state byte moved from the stdlib offset. ASan checks the tail.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER [--stdlib]}"
mode="${2:-np}"
compile_flags=(--no-prelude)
work="$(mktemp -d "${TMPDIR:-/tmp}/hash-literal-layout.XXXXXX")"
trap 'rm -rf "$work"' EXIT
indices_type="${HASH_INDICES_TYPE:-UInt8}"
case "$indices_type" in
  UInt8) indices_literal=1_u8 ;;
  Int8) indices_literal=1_i8 ;;
  *) echo "HASH_INDICES_TYPE must be UInt8 or Int8" >&2; exit 2 ;;
esac
cat > "$work/repro.cr" <<'CR'
class Hash(K, V)
  @a : UInt64 = 0_u64
  @indices_bytesize : INDICES_TYPE = INDICES_LITERAL
  @b : UInt64 = 0_u64
  @c : UInt64 = 0_u64
  @d : UInt64 = 0_u64
  @e : UInt64 = 0_u64
  @f : UInt64 = 0_u64
  @tail : UInt64 = 0_u64

  def tail : UInt64
    @tail
  end

  def indices_width : INDICES_TYPE
    @indices_bytesize
  end
end
h = {} of Int32 => Int32
exit 11 unless h.tail == 0_u64
exit 12 unless h.indices_width == INDICES_LITERAL
CR
sed -i.bak \
  -e "s/INDICES_TYPE/${indices_type}/g" \
  -e "s/INDICES_LITERAL/${indices_literal}/g" \
  "$work/repro.cr"
rm -f "$work/repro.cr.bak"
if [[ "$mode" == --stdlib ]]; then
  compile_flags=()
  cat > "$work/repro.cr" <<'CR'
h = {} of String => Int32
copy = h.dup
exit 11 unless copy.empty?
h["answer"] = 42
copy = h.dup
exit 12 unless copy["answer"] == 42
copy["answer"] = 7
exit 13 unless h["answer"] == 42
CR
elif [[ "$mode" != np ]]; then
  echo "unknown mode: $mode" >&2
  exit 2
fi

run_logged() {
  local log="$1"
  shift
  if ! "$@" > "$work/$log" 2>&1; then
    cat "$work/$log"
    return 1
  fi
}
run_logged compile.log "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/repro.cr" "${compile_flags[@]}" -o "$work/repro"
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
run_logged asan-run.log env ASAN_OPTIONS=detect_leaks=0 "$root/scripts/run_safe.sh" "$work/asan" 5 512
printf 'PASS[%s]: Hash literal layout and runtime controls under ASan\n' "$mode"
