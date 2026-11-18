#!/usr/bin/env bash
# Emit HIR, MIR, and LLVM IR for one compiler/corpus pair under run_safe.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/emit_bootstrap_ir.sh <compiler> <source.cr> <out-prefix> [compiler flags...]

Environment:
  BOOTSTRAP_IR_TIMEOUT_SEC  run_safe timeout per emit step (default: 120)
  BOOTSTRAP_IR_MEM_MB       run_safe RSS cap per emit step (default: 4096)

Outputs:
  <out-prefix>.hir
  <out-prefix>.mir
  <out-prefix>.ll
  <out-prefix>.<kind>.log
USAGE
}

if [[ $# -lt 3 ]]; then
  usage >&2
  exit 2
fi

COMPILER="$1"
SRC="$2"
OUT_PREFIX="$3"
shift 3

TIMEOUT_SEC="${BOOTSTRAP_IR_TIMEOUT_SEC:-120}"
MEM_MB="${BOOTSTRAP_IR_MEM_MB:-4096}"

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler is not executable: $COMPILER" >&2
  exit 2
fi
if [[ ! -f "$SRC" ]]; then
  echo "error: source not found: $SRC" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT_PREFIX")"

# Concurrent stages must use different prefixes so a run cannot claim another
# compiler's intermediate or published files.
LOCK_DIR="$OUT_PREFIX.emit.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "error: bootstrap IR output prefix is already in use: $OUT_PREFIX" >&2
  exit 1
fi
cleanup() {
  if (( $? != 0 )); then
    rm -f -- "$OUT_PREFIX.hir" "$OUT_PREFIX.mir" "$OUT_PREFIX.ll"
  fi
  rmdir "$LOCK_DIR"
}
trap cleanup EXIT

for kind in hir mir ll; do
  rm -f -- "$OUT_PREFIX.$kind" "$OUT_PREFIX.$kind.out.$kind"
done

run_emit() {
  local kind="$1"
  shift
  local stem="$OUT_PREFIX.$kind.out"
  local log="$OUT_PREFIX.$kind.log"
  local artifact="$stem.$kind"
  local wrapper="$OUT_PREFIX.$kind.sh"

  case "$kind" in
    hir)
      {
        echo "#!/usr/bin/env bash"
        echo "set -euo pipefail"
        echo "export ADAMAS_STOP_AFTER_HIR=1"
        printf 'exec'
        printf ' %q' "$COMPILER" "$SRC" --no-prelude --no-link --emit hir -o "$stem" "$@"
        echo
      } >"$wrapper"
      ;;
    mir)
      {
        echo "#!/usr/bin/env bash"
        echo "set -euo pipefail"
        echo "export ADAMAS_STOP_AFTER_MIR=1"
        printf 'exec'
        printf ' %q' "$COMPILER" "$SRC" --no-prelude --no-link --emit mir -o "$stem" "$@"
        echo
      } >"$wrapper"
      ;;
    ll)
      artifact="$stem.ll"
      {
        echo "#!/usr/bin/env bash"
        echo "set -euo pipefail"
        printf 'exec'
        printf ' %q' "$COMPILER" "$SRC" --no-prelude --no-link --emit llvm-ir -o "$stem" "$@"
        echo
      } >"$wrapper"
      ;;
    *)
      echo "error: internal unknown emit kind: $kind" >&2
      exit 2
      ;;
  esac
  chmod +x "$wrapper"

  "$ROOT_DIR/scripts/run_safe.sh" "$wrapper" "$TIMEOUT_SEC" "$MEM_MB" >"$log" 2>&1

  if [[ ! -f "$artifact" || -L "$artifact" || ! -s "$artifact" ]]; then
    echo "error: expected $kind artifact missing: $artifact" >&2
    tail -n 80 "$log" >&2 || true
    exit 1
  fi
}

run_emit hir "$@"
run_emit mir "$@"
run_emit ll "$@"

for kind in hir mir ll; do
  cp -- "$OUT_PREFIX.$kind.out.$kind" "$OUT_PREFIX.$kind"
done

echo "emit_bootstrap_ir_ok prefix=$OUT_PREFIX"
