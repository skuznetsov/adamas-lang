#!/usr/bin/env bash
# String's generic ToUnsignedInfo return must retain the concrete field width.
# Full prelude is intentional: this exercises the unchanged Crystal stdlib.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/string-wide-integer.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == 1 ]]; then
    echo "kept_tmp=$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

failed=0
for order in narrow_first wide_first; do
  src="$WORK_DIR/$order.cr"
  out="$WORK_DIR/$order"
  cat >"$src" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
CR
  if [[ "$order" == narrow_first ]]; then
    printf '%s\n' 'small = "12".to_u32?' 'wide = "4294967296".to_u64?' >>"$src"
  else
    printf '%s\n' 'wide = "4294967296".to_u64?' 'small = "12".to_u32?' >>"$src"
  fi
  cat >>"$src" <<'CR'
# Derive expected values from representable inputs so a generated compiler's
# broken wide-literal parser cannot make both sides identically wrong.
expected = 2147483648_u64 + 2147483648_u64
LibC.exit(11) unless small == 12_u32
LibC.exit(12) unless wide == expected
LibC.exit(13) unless "4294967297".to_u64? == expected + 1_u64
LibC.exit(14) unless "100000000".to_u64?(16) == expected
LibC.exit(15) unless "-4294967296".to_i64? == -(2147483648_i64 + 2147483648_i64)
LibC.exit(16) unless "invalid".to_u64?.nil?
LibC.exit(0)
CR
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 8192 \
      "$src" -o "$out" >"$out.compile.log" 2>&1; then
    echo "FAIL: $order compilation" >&2
    tail -30 "$out.compile.log" >&2
    failed=1
    continue
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$out" 5 512 >"$out.run.log" 2>&1; then
    echo "FAIL: $order integer return contract" >&2
    cat "$out.run.log" >&2
    failed=1
  else
    echo "PASS: $order integer return contract"
  fi
done
exit "$failed"
