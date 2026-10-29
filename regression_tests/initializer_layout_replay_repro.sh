#!/usr/bin/env bash
# Layout invalidation must replay the exact selected initializer, even after
# pending callsites are consumed and without a separate RTA demand.
# The HIR specs check body identity, caller isolation and stale-evidence guards.
# The installed-prelude check covers compilation/linking only; it deliberately
# makes no claim about the separate prelude startup/runtime frontier.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT/bin/adamas}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-crystal}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/initializer_layout_replay.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SAFE="$ROOT/scripts/run_safe.sh"

if [[ -z "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_PATH="$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$ORIGINAL" 10 1024 env CRYSTAL_PATH)"
  export CRYSTAL_PATH
fi
export CRYSTAL_CACHE_DIR="$WORK/cache"
printf 'puts "hello"\n' > "$WORK/hello.cr"

link_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  link_flags+=(--link-flags=-fuse-ld=/usr/bin/ld)
fi
"$SAFE" "$ORIGINAL" 120 4096 build "$WORK/hello.cr" --no-debug \
  "${link_flags[@]}" -o "$WORK/original" > "$WORK/original.build.log" 2>&1 || {
  cat "$WORK/original.build.log" >&2
  exit 1
}
RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/original" 5 512 \
  > "$WORK/original.stdout" 2> "$WORK/original.run.log"
printf 'hello\n' > "$WORK/expected"
cmp "$WORK/expected" "$WORK/original.stdout"

(cd "$ROOT" && "$SAFE" "$ORIGINAL" 180 14336 spec \
  spec/hir/initializer_layout_replay_spec.cr \
  spec/hir/materialized_initializer_source_spec.cr \
  spec/hir/pending_queue_layout_invalidation_spec.cr \
  "${link_flags[@]}" --single-module --no-debug) > "$WORK/spec.log" 2>&1 || {
  cat "$WORK/spec.log" >&2
  exit 1
}

"$SAFE" "$COMPILER" 180 8192 "$WORK/hello.cr" --no-debug \
  --no-ast-cache --no-llvm-cache -o "$WORK/candidate" > "$WORK/candidate.build.log" 2>&1 || {
  cat "$WORK/candidate.build.log" >&2
  exit 1
}
test -s "$WORK/candidate"
python3 - "$WORK/candidate.ll" <<'PY'
import re
import sys
from pathlib import Path

ir = Path(sys.argv[1]).read_text()
name = "Thread$Hinitialize$$String_block"
body = re.search(r"^define void @" + re.escape(name) + r"\([^\n]*\) \{\n(.*?)^\}", ir, re.M | re.S)
assert body, "the allocator's exact concrete initializer has no emitted body"
assert "@Thread$Hinit_semaphore(" in body[1], "wrong initializer source body"
assert "@Thread$Hinit_handle(" in body[1], "incomplete initializer source body"
assert "@abort(" not in body[1], "initializer was replaced by an abort stub"
PY
echo "PASS: exact initializer replay and stale-source guards; installed prelude compiles and links"
