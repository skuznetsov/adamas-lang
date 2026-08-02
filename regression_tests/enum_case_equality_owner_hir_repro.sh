#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SOURCE="$ROOT_DIR/regression_tests/enum_case_equality_owner_hir_repro.cr"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum_case_equality_owner.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found or not executable: $COMPILER" >&2
  exit 2
fi

WRAPPER="$WORK_DIR/run.sh"
LOG="$WORK_DIR/run.log"
ARTIFACT="$WORK_DIR/out.hir"

{
  echo "#!/usr/bin/env bash"
  echo "set -euo pipefail"
  echo "export ADAMAS_STOP_AFTER_HIR=1"
  printf 'exec %q ' "$COMPILER"
  printf '%q ' --no-prelude --no-ast-cache --emit hir
  printf '%q ' "$SOURCE" --no-link -o "$WORK_DIR/out"
  echo
} >"$WRAPPER"
chmod +x "$WRAPPER"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$WRAPPER" 40 2048 >"$LOG" 2>&1
STATUS=$?
set -e

if [[ $STATUS -ne 0 || ! -f "$ARTIFACT" ]]; then
  echo "reproduced: compiler failed before the enum case-equality HIR oracle" >&2
  tail -n 80 "$LOG" >&2 || true
  exit 1
fi

exact_count="$(rg -c -F 'CaseKind#===$CaseKind' "$ARTIFACT" || true)"
nilable_count="$(rg -c -F 'CaseKind#===$Nil | CaseKind' "$ARTIFACT" || true)"
object_count="$(rg -c -F 'Object#===' "$ARTIFACT" || true)"
integer_count="$(rg -c 'Int(32|64)#===' "$ARTIFACT" || true)"
carrier_count="$(rg -c 'func @CaseKind#===.*\(%0: 4,' "$ARTIFACT" || true)"

if [[ "${exact_count:-0}" != "2" ||
      "${nilable_count:-0}" != "2" ||
      "${object_count:-0}" != "0" ||
      "${integer_count:-0}" != "0" ||
      "${carrier_count:-0}" != "2" ]]; then
  echo "reproduced: enum case-equality owner or receiver ABI drifted" >&2
  echo "exact=${exact_count:-0} nilable=${nilable_count:-0} object=${object_count:-0} integer=${integer_count:-0} carrier=${carrier_count:-0}" >&2
  rg -n 'CaseKind#===|Object#===|Int(32|64)#===' "$ARTIFACT" >&2 || true
  exit 1
fi

echo "not reproduced: enum case-equality owners and carrier ABI are preserved"
