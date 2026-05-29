#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SRC="$ROOT_DIR/regression_tests/stage2_builtin_nil_alias_repro.cr"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_builtin_nil_alias_repro.XXXXXX")"
WRAPPER="$WORKDIR/run.sh"
LOG="$WORKDIR/run.log"
OUT_BASE="$WORKDIR/out"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

cat >"$WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export ADAMAS_STOP_AFTER_HIR=1
export ADAMAS_TRUST_SLICE_ADDR=1
export DEBUG_CLASS_ARENA='Crystal::Once::Operation'
export DEBUG_CLASS_REPAIR='Crystal::Once::Operation'
export DEBUG_REG_CONCRETE_PHASE='Crystal::Once::Operation'
export DEBUG_RECEIVER_FIELD='resume_all'
export DEBUG_REG_METHOD_PHASE='resume_all'
export DEBUG_RESOLVE_TYPE_CTX='Nil'
export DEBUG_RESOLVE_CLASS_CTX='Nil'
exec "$COMPILER" "$SRC" --release --no-prelude --no-ast-cache --emit hir -o "$OUT_BASE"
EOF
chmod +x "$WRAPPER"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$WRAPPER" 20 1024 >"$LOG" 2>&1
run_status=$?
set -e

if grep -Fq 'phase=resolved_return raw=Nil resolved=Crystal::PointerLinkedList::Node::Nil' "$LOG"; then
  echo "reproduced: builtin Nil still leaks through alias fallback to Crystal::PointerLinkedList::Node::Nil"
  tail -n 120 "$LOG"
  exit 1
fi

if grep -Fq 'phase=return_contextual_alias name=Nil target=Crystal::PointerLinkedList::Node::Nil' "$LOG"; then
  echo "reproduced: builtin Nil still leaks through contextual alias fallback"
  tail -n 120 "$LOG"
  exit 1
fi

if grep -Fq 'phase=return_suffix_alias name=Nil target=Crystal::PointerLinkedList::Node::Nil' "$LOG"; then
  echo "reproduced: builtin Nil still leaks through suffix alias fallback"
  tail -n 120 "$LOG"
  exit 1
fi

if grep -Fq 'phase=resolved_return raw=Nil resolved=Nil' "$LOG"; then
  echo "not reproduced: builtin Nil stays builtin across contextual/suffix alias fallbacks"
  exit 0
fi

echo "inconclusive: expected return-type trace not found"
tail -n 120 "$LOG" >&2 || true
exit 2
