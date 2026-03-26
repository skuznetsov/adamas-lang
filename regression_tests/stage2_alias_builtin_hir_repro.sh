#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <stage1-compiler> <stage2-compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT_DIR/regression_tests/stage2_alias_builtin_hir_repro.cr"
STAGE1="$1"
STAGE2="$2"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_alias_builtin_hir.XXXXXX")"

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

run_hir() {
  local label="$1"
  local compiler="$2"
  local wrapper="$WORKDIR/${label}.sh"
  local log="$WORKDIR/${label}.log"

  {
    echo "#!/usr/bin/env bash"
    echo "set -euo pipefail"
    echo "export CRYSTAL_V2_STOP_AFTER_HIR=1"
    echo "export CRYSTAL_V2_TRACE_ALIAS_ROOT=1"
    printf 'exec %q ' "$compiler"
    printf '%q ' "$SRC" --release --no-prelude --emit hir -o "$WORKDIR/${label}_out"
    echo
  } >"$wrapper"
  chmod +x "$wrapper"

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$wrapper" 20 2048 >"$log" 2>&1
  local status=$?
  set -e

  echo "$status"
}

assert_no_alias_segfault() {
  local label="$1"
  local status="$2"
  local log="$WORKDIR/${label}.log"

  case "$status" in
    0|134)
      ;;
    138|139)
      echo "reproduced: ${label} still dies in the old top-level alias segfault corridor" >&2
      tail -n 120 "$log" >&2 || true
      exit 1
      ;;
    *)
      echo "inconclusive: unexpected ${label} exit status ${status}" >&2
      tail -n 120 "$log" >&2 || true
      exit 2
      ;;
  esac

}

assert_stage2_alias_trace() {
  local log="$WORKDIR/stage2.log"

  if ! rg -q '\[ALIAS_ROOT\] phase=register_alias.after_store' "$log"; then
    echo "reproduced: stage2 did not finish top-level alias registration" >&2
    tail -n 120 "$log" >&2 || true
    exit 1
  fi
}

stage1_status="$(run_hir stage1 "$STAGE1")"
assert_no_alias_segfault stage1 "$stage1_status"

stage2_status="$(run_hir stage2 "$STAGE2")"
assert_no_alias_segfault stage2 "$stage2_status"
assert_stage2_alias_trace

echo "not reproduced: stage2 survives the top-level alias HIR oracle past alias registration"
