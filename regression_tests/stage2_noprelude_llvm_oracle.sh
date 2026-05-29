#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <stage1-compiler> <stage2-compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="$1"
STAGE2="$2"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_noprelude_llvm.XXXXXX")"

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

run_phase() {
  local case_name="$1"
  local label="$2"
  local compiler="$3"
  local emit_kind="$4"
  local wrapper="$WORKDIR/${case_name}.${label}.${emit_kind}.sh"
  local log="$WORKDIR/${case_name}.${label}.${emit_kind}.log"
  local out_base="$WORKDIR/${case_name}.${label}.${emit_kind}"
  local artifact

  case "$emit_kind" in
    mir)
      artifact="${out_base}.mir"
      {
        echo "#!/usr/bin/env bash"
        echo "set -euo pipefail"
        echo "export ADAMAS_STOP_AFTER_MIR=1"
        printf 'exec %q ' "$compiler"
        printf '%q ' --release --no-prelude --no-ast-cache --emit mir --no-link
        printf '%q ' "$WORKDIR/${case_name}.cr" -o "$out_base"
        echo
      } >"$wrapper"
      ;;
    llvm)
      artifact="${out_base}.ll"
      {
        echo "#!/usr/bin/env bash"
        echo "set -euo pipefail"
        printf 'exec %q ' "$compiler"
        printf '%q ' --release --no-prelude --no-ast-cache --emit llvm-ir --no-link
        printf '%q ' "$WORKDIR/${case_name}.cr" -o "$out_base"
        echo
      } >"$wrapper"
      ;;
    *)
      echo "error: unknown emit kind: $emit_kind" >&2
      exit 2
      ;;
  esac

  chmod +x "$wrapper"

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$wrapper" 30 2048 >"$log" 2>&1
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    if [[ $label == stage1 ]]; then
      echo "inconclusive: stage1 failed on ${case_name}/${emit_kind}" >&2
      tail -n 120 "$log" >&2 || true
      exit 2
    fi
    echo "reproduced: stage2 failed on ${case_name}/${emit_kind}"
    tail -n 120 "$log"
    exit 1
  fi

  if [[ ! -f "$artifact" ]]; then
    echo "inconclusive: expected artifact missing: $artifact" >&2
    tail -n 120 "$log" >&2 || true
    exit 2
  fi
}

compare_phase() {
  local case_name="$1"
  local emit_kind="$2"
  local ext

  case "$emit_kind" in
    mir) ext="mir" ;;
    llvm) ext="ll" ;;
    *)
      echo "error: unknown emit kind: $emit_kind" >&2
      exit 2
      ;;
  esac

  run_phase "$case_name" stage1 "$STAGE1" "$emit_kind"
  run_phase "$case_name" stage2 "$STAGE2" "$emit_kind"

  if ! diff -u \
    "$WORKDIR/${case_name}.stage1.${emit_kind}.${ext}" \
    "$WORKDIR/${case_name}.stage2.${emit_kind}.${ext}" \
    >"$WORKDIR/${case_name}.${emit_kind}.diff"; then
    echo "reproduced: stage2 diverges from stage1 on ${case_name}/${emit_kind}"
    sed -n '1,160p' "$WORKDIR/${case_name}.${emit_kind}.diff"
    exit 1
  fi
}

printf '1\n' >"$WORKDIR/literal.cr"
printf '1 + 2\n' >"$WORKDIR/add.cr"

for case_name in literal add; do
  compare_phase "$case_name" mir
  compare_phase "$case_name" llvm
done

echo "not reproduced: stage2 matches stage1 for no-prelude MIR and LLVM oracles"
