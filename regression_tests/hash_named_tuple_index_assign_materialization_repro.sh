#!/usr/bin/env bash
# Regression: in the full compiler context, Hash(UInt64, NamedTuple)#[]= could
# be materialized under a Tuple-valued target symbol while the actual call kept
# the NamedTuple-valued symbol. The call then fell through to an aborting
# undefined-extern stub in the self-compiled compiler.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_namedtuple_index_assign.XXXXXX")"
OUT="$TMP_DIR/adamas_self"
RUN_OUT="$TMP_DIR/compile.out"
trap 'rm -rf "$TMP_DIR"' EXIT

set +e
./scripts/run_safe.sh "$COMPILER" 240 8192 src/adamas.cr -o "$OUT" --emit llvm-ir --no-link >"$RUN_OUT" 2>&1
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "FAIL: compiler self-IR build failed (status $status)"
  tail -80 "$RUN_OUT"
  exit 2
fi

LL="${OUT}.ll"
if [[ ! -f "$LL" ]]; then
  echo "FAIL: expected LLVM IR was not written: $LL"
  tail -80 "$RUN_OUT"
  exit 2
fi

stub_def="$(awk '
  /^define .*Hash.*class_name.*method_name.*is_class.*IDXS/ {
    in_def = 1
    body = $0 "\n"
    next
  }
  in_def {
    body = body $0 "\n"
    if ($0 == "}") {
      if (body ~ /STUB CALLED/ || body ~ /@abort/) {
        print body
        exit 0
      }
      in_def = 0
      body = ""
    }
  }
' "$LL")"
if [[ -n "$stub_def" ]]; then
  echo "FAIL: Hash(UInt64, NamedTuple)#[]= still lowers to an abort stub"
  echo "$stub_def" | head -40
  exit 1
fi

if grep -q 'define .*Hash.*class_name.*method_name.*is_class.*IDXS' "$LL"; then
  echo "PASS: Hash(UInt64, NamedTuple)#[]= has a non-stub materialization"
  exit 0
fi

echo "FAIL: no Hash(UInt64, NamedTuple)#[]= materialization found"
exit 1
