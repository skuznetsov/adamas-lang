#!/usr/bin/env bash
# Qualify the exact select result before the separate timer pointer runtime path.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--lgc -fuse-ld=/usr/bin/ld}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/channel-select-result.XXXXXX")"

cleanup() {
  local result=$?
  rm -rf -- "$WORK_DIR"/cache-*
  if [[ "$result" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$ADAMAS_BIN" || ! -x "$ORIGINAL_CRYSTAL_BIN" ||
      ! -x "$SAFE_RUNNER" || ! -f "$CRYSTAL_STDLIB/prelude.cr" ]]; then
  echo 'ERROR: candidate, original Crystal, safe runner, and stock stdlib are required' >&2
  exit 2
fi

cat >"$WORK_DIR/select.cr" <<'CRYSTAL'
def run_timeout
  channel = Channel(Nil).new
  select
  when channel.receive?
    puts "unexpected receive"
  when timeout(0.seconds)
    puts "timeout"
  end
end

def run_receive
  channel = Channel(String).new(1)
  channel.send("ready")
  select
  when value = channel.receive?
    puts value
  when timeout(10.seconds)
    puts "unexpected timeout"
  end
end

run_timeout
run_receive
CRYSTAL

CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache-original" \
  "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 \
  build "$WORK_DIR/select.cr" --no-debug "--link-flags=$LINK_FLAGS" \
  -o "$WORK_DIR/original" >"$WORK_DIR/original.compile.log" 2>&1
RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/original" 5 512 \
  >"$WORK_DIR/original.stdout" 2>"$WORK_DIR/original.run.log"
printf 'timeout\nready\n' >"$WORK_DIR/expected"
diff -u "$WORK_DIR/expected" "$WORK_DIR/original.stdout"

CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache-candidate" \
  DEBUG_FORCE_LOWER_DEPTH=1 ADAMAS_LLVM_CACHE=0 \
  env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO \
  "$SAFE_RUNNER" "$ADAMAS_BIN" 180 8192 "$WORK_DIR/select.cr" \
  --no-debug --no-ast-cache --no-llvm-cache --emit hir --no-link \
  -o "$WORK_DIR/candidate" >"$WORK_DIR/candidate.compile.log" 2>&1

python3 - "$WORK_DIR/candidate.hir" <<'PY'
from pathlib import Path
import re
import sys

hir = Path(sys.argv[1]).read_text()
descriptors = dict(re.findall(r"^  type\.(\d+) = (.+)$", hir, re.MULTILINE))
functions = re.findall(r"^func @(.+)\([^\n]* -> (\d+) \{$", hir, re.MULTILINE)
for value_type in ("Nil", "String"):
    suffix = (
        ".select_impl$Tuple(Channel::LooseReceiveAction("
        + value_type
        + "), Channel::TimeoutAction)_Bool"
    )
    results = [descriptors[result] for name, result in functions if name.endswith(suffix)]
    assert len(results) == 1, (value_type, results)
    match = re.fullmatch(r"Tuple Tuple\(Int32, (.+)\)\([^)]*\)", results[0])
    assert match, results[0]
    expected = {"Nil", "Channel::NotReady"}
    if value_type == "String":
        expected.add("String")
    assert set(match[1].split(" | ")) == expected, results[0]
    print(f"PASS Channel({value_type}) exact select result")
PY

echo 'PASS stock native select and candidate HIR result contracts'
