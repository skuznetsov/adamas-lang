#!/usr/bin/env bash
# Keep invocation defines consistent through declarations, method bodies and macros.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${1:-${ADAMAS_BIN:-}}"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_PATH="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
[[ -x "$SAFE_RUNNER" && -x "$CRYSTAL_BIN" && -d "$CRYSTAL_PATH" ]]
if [[ "$ORIGINAL_ONLY" != 1 ]]; then
  [[ -x "$ADAMAS_BIN" ]] || { echo 'pass an Adamas compiler path' >&2; exit 2; }
  ADAMAS_BIN="$(cd "$(dirname "$ADAMAS_BIN")" && pwd -P)/$(basename "$ADAMAS_BIN")"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/compile-time-define.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib DefineContractC
  fun putchar(value : Int32) : Int32
  fun exit(code : Int32) : NoReturn
end

{% if flag?(:contract_feature) %}
  def declared_flag : Int32
    DefineContractC.putchar(65)
  end
{% else %}
  def declared_flag : Int32
    DefineContractC.putchar(66)
  end
{% end %}

macro expand_flag
  {% if flag?(:contract_feature) %}
    DefineContractC.putchar(67)
  {% else %}
    DefineContractC.putchar(68)
  {% end %}
end

def method_flag : Int32
  {% if flag?(:contract_feature) %}
    DefineContractC.putchar(69)
  {% else %}
    DefineContractC.putchar(70)
  {% end %}
end

declared_flag
expand_flag
method_flag
DefineContractC.putchar(10)
DefineContractC.exit(0)
CRYSTAL

printf 'probe_sha256=%s\n' "$(shasum -a 256 "$WORK_DIR/probe.cr" | awk '{print $1}')"

build_and_run() {
  local label="$1" compiler="$2" mode="$3" expected="$4" status=0
  shift 4
  local prefix="$WORK_DIR/$label-$mode" cache="$WORK_DIR/$label-$mode.cache"
  if [[ "$label" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$prefix.build.resources" \
      "$SAFE_RUNNER" "$compiler" 120 8192 build "$WORK_DIR/probe.cr" \
      --prelude=empty "$@" -o "$prefix.bin" --link-flags=-fuse-ld=/usr/bin/ld \
      >"$prefix.build.log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      RUN_SAFE_RESOURCE_FILE="$prefix.build.resources" \
      "$SAFE_RUNNER" "$compiler" 120 8192 "$WORK_DIR/probe.cr" \
      --no-prelude --no-ast-cache --no-llvm-cache "$@" -o "$prefix.bin" \
      >"$prefix.build.log" 2>&1 || status=$?
  fi
  rm -rf "$cache"
  [[ "$status" -eq 0 ]] || { cat "$prefix.build.log" >&2; return 1; }

  status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$prefix.run.resources" \
    "$SAFE_RUNNER" "$prefix.bin" 5 512 \
    >"$prefix.stdout" 2>"$prefix.run.log" || status=$?
  [[ "$status" -eq 0 ]] && grep -Fq '[EXIT: 0]' "$prefix.run.log" || {
    cat "$prefix.run.log" >&2; return 1;
  }
  printf '%s\n' "$expected" >"$prefix.expected"
  diff -u "$prefix.expected" "$prefix.stdout"
}

for label in original candidate; do
  [[ "$label" != candidate || "$ORIGINAL_ONLY" != 1 ]] || continue
  compiler="$CRYSTAL_BIN"
  [[ "$label" != candidate ]] || compiler="$ADAMAS_BIN"
  build_and_run "$label" "$compiler" absent BDF
  build_and_run "$label" "$compiler" short_joined ACE -Dcontract_feature
  build_and_run "$label" "$compiler" short_separate ACE -D contract_feature
  build_and_run "$label" "$compiler" long_separate ACE --define contract_feature
  build_and_run "$label" "$compiler" long_equals ACE --define=contract_feature
done

printf 'PASS: compile-time defines select the same declarations, macro output and method bodies as original Crystal\n'
