#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <stage1-compiler> <stage2-compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="$1"
STAGE2="$2"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_full_parse_macro_expander.XXXXXX")"
FULL_SRC="$ROOT_DIR/src/crystal_v2.cr"
MACRO_EXPANDER_SRC="$ROOT_DIR/src/compiler/semantic/macro_expander.cr"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

for compiler in "$STAGE1" "$STAGE2"; do
  if [[ ! -x "$compiler" ]]; then
    echo "error: compiler binary not found/executable: $compiler" >&2
    exit 2
  fi
done

run_parse_only() {
  local label="$1"
  local compiler="$2"
  local source_file="$3"
  local log="$WORKDIR/${label}.log"
  local wrapper="$WORKDIR/${label}.sh"

  {
    echo "#!/usr/bin/env bash"
    echo "set -euo pipefail"
    echo "export CRYSTAL_V2_STOP_AFTER_PARSE=1"
    printf 'exec %q ' "$compiler"
    printf '%q ' "$source_file" --release -o "$WORKDIR/${label}_out"
    echo
  } >"$wrapper"
  chmod +x "$wrapper"

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$wrapper" 180 8192 >"$log" 2>&1
  local status=$?
  set -e

  echo "$status"
}

stage1_direct_rc="$(run_parse_only stage1_direct "$STAGE1" "$MACRO_EXPANDER_SRC")"
if [[ "$stage1_direct_rc" != "0" ]]; then
  echo "inconclusive: stage1 failed on direct macro_expander parse-only control" >&2
  tail -n 80 "$WORKDIR/stage1_direct.log" >&2 || true
  exit 2
fi

stage2_direct_rc="$(run_parse_only stage2_direct "$STAGE2" "$MACRO_EXPANDER_SRC")"
if [[ "$stage2_direct_rc" != "0" ]]; then
  echo "inconclusive: stage2 failed on direct macro_expander parse-only control" >&2
  tail -n 80 "$WORKDIR/stage2_direct.log" >&2 || true
  exit 2
fi

stage1_full_rc="$(run_parse_only stage1_full "$STAGE1" "$FULL_SRC")"
if [[ "$stage1_full_rc" != "0" ]]; then
  echo "inconclusive: stage1 failed on full-project parse-only control" >&2
  tail -n 80 "$WORKDIR/stage1_full.log" >&2 || true
  exit 2
fi

stage2_full_rc="$(run_parse_only stage2_full "$STAGE2" "$FULL_SRC")"
if [[ "$stage2_full_rc" == "0" ]]; then
  echo "not reproduced: stage2 survived full-project parse-only through macro_expander"
  exit 0
fi

if ! rg -q 'macro_expander\.cr' "$WORKDIR/stage2_full.log"; then
  echo "inconclusive: stage2 full-project parse-only failed, but macro_expander was not in the terminal trace" >&2
  tail -n 80 "$WORKDIR/stage2_full.log" >&2 || true
  exit 2
fi

echo "reproduced: stage2 crashes during accumulated full-project parse when it reaches macro_expander"
tail -n 120 "$WORKDIR/stage2_full.log"
exit 1
