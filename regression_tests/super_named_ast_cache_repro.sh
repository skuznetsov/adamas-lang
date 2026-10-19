#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
if [[ "$ORIGINAL" != */* ]]; then ORIGINAL="$(command -v "$ORIGINAL")"; fi
[[ -x "$ORIGINAL" && -x "$SAFE" ]] || { printf 'missing original Crystal or safe runner\n' >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas_super_cache.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
export CRYSTAL_CACHE_DIR="$WORK/host_cache" XDG_CACHE_HOME="$WORK/ast_cache"
LINK=()
if [[ "$(uname -s)" == Darwin ]]; then LINK=(--link-flags=-fuse-ld=/usr/bin/ld); fi
# This tests the cache API itself using the original host compiler. The CLI's
# cache loader is disabled, so this makes no claim about CLI cache hits.
if ! "$SAFE" "$ORIGINAL" 180 4096 build "$ROOT/regression_tests/super_named_ast_cache_repro.cr" \
  --no-debug --single-module --error-trace "${LINK[@]}" -o "$WORK/probe" >"$WORK/compile.log" 2>&1; then
  cat "$WORK/compile.log" >&2; exit 1
fi
if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/probe" 5 512 "$WORK/runtime" >"$WORK/stdout" 2>"$WORK/stderr"; then
  cat "$WORK/stdout"; cat "$WORK/stderr" >&2; exit 1
fi
cat >"$WORK/expected" <<'EXPECTED'
PASS: old-version rejection
PASS: named super argument and shared value identity
PASS: spans and absent versus empty arguments
EXPECTED
cmp "$WORK/expected" "$WORK/stdout"
python3 - "$WORK/stderr" <<'PY_STDERR'
import re,sys
from pathlib import Path
raw=Path(sys.argv[1]).read_bytes()
pattern=rb'\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?'
assert re.fullmatch(pattern,raw), 'unexpected runtime stderr'
assert b'outcome=exit' in raw and b'reason=exit' in raw and b'exit_code=0' in raw
PY_STDERR
cat "$WORK/stdout"
