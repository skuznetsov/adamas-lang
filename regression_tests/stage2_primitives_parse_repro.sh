#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_primitives_parse.XXXXXX")"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

WRAPPER="$WORKDIR/primitives_parse.sh"
LOG="$WORKDIR/primitives_parse.log"

cat >"$WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export ADAMAS_STOP_AFTER_PARSE=1
exec "$COMPILER" --release --no-ast-cache "$ROOT_DIR/src/stdlib/primitives.cr" -o "$WORKDIR/primitives_parse.out"
EOF
chmod +x "$WRAPPER"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$WRAPPER" 20 2048 >"$LOG" 2>&1
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  echo "reproduced: self-hosted compiler still crashes while parse-scanning src/stdlib/primitives.cr"
  tail -n 120 "$LOG"
  exit 1
fi

echo "not reproduced: self-hosted compiler survives parse-only scan of src/stdlib/primitives.cr"
