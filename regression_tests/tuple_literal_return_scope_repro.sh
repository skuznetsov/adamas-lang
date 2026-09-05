#!/usr/bin/env bash
# Local tuples retain their own types; only actual returns adopt the declared
# tuple ABI. Covers explicit/implicit nullable returns and a same-arity key.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/tuple_return_scope.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == 1 ]]; then
    echo "kept_tmp=$WORKDIR"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT
cat >"$WORKDIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def key_weight(key : {Int64, Int32}) : Int32
  (key[0] >> 32).to_i32 * 10 + key[1]
end

def local_pair(left : Int64, right : Int32) : {Int32, Int32}
  key = {left, right}
  {key_weight(key), 7}
end

def implicit_nullable : {Int32?, Int32?}
  {nil, 1}
end

def explicit_nullable : {Int32?, Int32?}
  return {2, nil}
end

pair = local_pair(2147483648_i64 + 2147483648_i64, 1)
LibC.exit(81) unless pair[0] == 11 && pair[1] == 7
implicit = implicit_nullable
LibC.exit(82) unless implicit[0].nil? && implicit[1] == 1
explicit = explicit_nullable
LibC.exit(83) unless explicit[0] == 2 && explicit[1].nil?
LibC.exit(0)
CR
for mode in original adamas; do
  if [[ "$mode" == original ]]; then
    build=("${ORIGINAL_CRYSTAL:-crystal}" 120 8192 build "$WORKDIR/repro.cr")
  else
    build=("$COMPILER" 120 8192 "$WORKDIR/repro.cr" --no-prelude)
  fi
  if ! CRYSTAL_CACHE_DIR="$WORKDIR/cache" "$ROOT_DIR/scripts/run_safe.sh" \
    "${build[@]}" -o "$WORKDIR/$mode.bin" >"$WORKDIR/$mode.compile.log" 2>&1; then
    echo "FAIL: $mode tuple return scope compilation" >&2
    tail -35 "$WORKDIR/$mode.compile.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORKDIR/$mode.bin" 5 512 \
    >"$WORKDIR/$mode.run.log" 2>&1; then
    echo "FAIL: $mode tuple return scope runtime" >&2
    cat "$WORKDIR/$mode.run.log" >&2
    exit 1
  fi
done
echo "PASS: local tuple identity and explicit/implicit nullable tuple returns"
