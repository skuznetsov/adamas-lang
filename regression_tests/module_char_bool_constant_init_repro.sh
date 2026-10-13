#!/usr/bin/env bash
# Module/class-scoped Char and Bool constants were never initialized: the HIR
# deferred no runtime init for CharNode (no macro literal exists for Char) and
# treated Bool literals as static, while cli.cr emitted static initializers
# only for integers. Both globals stayed zero, so File::SEPARATOR read as '\0'
# (S2 stdlib_source_path? false -> S3 "heterogeneous hash returns").
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module_char_bool_const.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_char_bool_const.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module Mm
  CH = 'b'
  EX = 3 + 4
  FL = 2.5
  TR = true
  FA = false
  ND = 7_u8
end
class Kk
  SEPK = 'a'
  YES = true
end
r = 0
r |= 1 unless Mm::CH.ord == 98
r |= 2 unless Mm::EX == 7
r |= 4 unless Mm::FL > 2.0
r |= 8 unless Mm::TR
r |= 16 unless Mm::ND == 7
r |= 32 if Mm::FA
r |= 64 unless Kk::SEPK.ord == 97
r |= 128 unless Kk::YES
LibC.exit(r == 0 ? 3 : (r & 0x3f) + 64)
CR
cat >"$WORK_DIR/file_separator_const.cr" <<'CR'
sep = File::SEPARATOR
exit(sep.ord == 47 && (sep.to_s + "x") == "/x" ? 3 : 1)
CR
for name in np_char_bool_const file_separator_const; do
  flags=()
  [[ "$name" == np_* ]] && flags=(--no-prelude)
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" ${flags[@]+"${flags[@]}"} -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    cat "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 3\]' "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT 3):" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo module_char_bool_constant_init_repro_ok
