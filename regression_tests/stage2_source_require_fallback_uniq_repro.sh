#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <stage1-compiler> <stage2-compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="$1"
STAGE2="$2"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_source_require_fallback_uniq.XXXXXX")"
PROBE_DIR="$WORKDIR/probe"
ROOT_FILE="$PROBE_DIR/root.cr"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

mkdir -p "$PROBE_DIR"

for compiler in "$STAGE1" "$STAGE2"; do
  if [[ ! -x "$compiler" ]]; then
    echo "error: compiler binary not found/executable: $compiler" >&2
    exit 2
  fi
done

for i in $(seq 1 17); do
  printf '# dep %s\n' "$i" > "$PROBE_DIR/dep_$i.cr"
done

: > "$ROOT_FILE"
for i in $(seq 1 17); do
  printf 'require "./dep_%s"\n' "$i" >> "$ROOT_FILE"
done
printf 'puts 1\n' >> "$ROOT_FILE"

run_parse_only() {
  local label="$1"
  local compiler="$2"
  local log="$WORKDIR/${label}.log"
  local wrapper="$WORKDIR/${label}.sh"

  {
    echo "#!/usr/bin/env bash"
    echo "set -euo pipefail"
    echo "export ADAMAS_STOP_AFTER_PARSE=1"
    printf 'exec %q ' "$compiler"
    printf '%q ' "$ROOT_FILE" --release --no-prelude --no-ast-cache -o "$WORKDIR/${label}_out"
    echo
  } >"$wrapper"
  chmod +x "$wrapper"

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$wrapper" 60 2048 >"$log" 2>&1
  local status=$?
  set -e

  echo "$status"
}

stage1_rc="$(run_parse_only stage1 "$STAGE1")"
if [[ "$stage1_rc" != "0" ]]; then
  echo "inconclusive: stage1 failed on the synthetic source-fallback control" >&2
  tail -n 80 "$WORKDIR/stage1.log" >&2 || true
  exit 2
fi

stage2_rc="$(run_parse_only stage2 "$STAGE2")"
if [[ "$stage2_rc" == "0" ]]; then
  echo "not reproduced: stage2 survived synthetic source-fallback require dedupe"
  exit 0
fi

if ! rg -q 'STUB CALLED: Set.*\[CRASH\] Abort \(exit 134\)|STUB CALLED: Set' "$WORKDIR/stage2.log"; then
  echo "inconclusive: stage2 failed, but not with the expected Set-backed dedupe abort" >&2
  tail -n 80 "$WORKDIR/stage2.log" >&2 || true
  exit 2
fi

echo "reproduced: stage2 aborts in source-fallback require dedupe on 17 local requires"
tail -n 120 "$WORKDIR/stage2.log"
exit 1
