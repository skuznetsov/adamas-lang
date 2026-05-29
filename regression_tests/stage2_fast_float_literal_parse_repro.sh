#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_fast_float_literal.XXXXXX")"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

SRC="$WORKDIR/float_literal.cr"
OUT="$WORKDIR/float_literal.out"
WRAPPER="$WORKDIR/float_literal.sh"

printf '1.5\n' >"$SRC"

cat >"$WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec env ADAMAS_STOP_AFTER_PARSE=1 "$COMPILER" "$SRC" -o "$OUT" --no-prelude
EOF
chmod +x "$WRAPPER"

set +e
OUTPUT="$("$ROOT_DIR/scripts/run_safe.sh" "$WRAPPER" 30 2048 2>&1)"
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  echo "reproduced: stage2 still aborts while parsing a float literal via FastFloat"
  echo "$OUTPUT" | tail -n 40
  exit 1
fi

echo "not reproduced: stage2 parses a float literal without FastFloat accessor stubs"
