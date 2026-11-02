#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal || true)}"
FIXTURE_DIR="$ROOT_DIR/spec/fixtures/macro_heredoc_source_slice"
FIXTURES=(
  macro_sibling.cr
  macro_multiple.cr
  macro_tail_block.cr
  macro_body_directive.cr
  macro_tail_directive.cr
  macro_control_body.cr
)

resolve_executable() {
  local requested="$1"
  [[ -n "$requested" ]] || return 0
  if [[ "$requested" == */* ]]; then
    local directory
    directory="$(cd "$(dirname "$requested")" && pwd)"
    printf '%s/%s\n' "$directory" "$(basename "$requested")"
  else
    command -v "$requested"
  fi
}

ADAMAS_BIN="$(resolve_executable "$ADAMAS_BIN")"
CRYSTAL_BIN="$(resolve_executable "$CRYSTAL_BIN")"

if [[ ! -x "$SAFE_RUNNER" ]]; then
  echo "missing safe runner: $SAFE_RUNNER" >&2
  exit 2
fi
if [[ ! -x "$ADAMAS_BIN" ]]; then
  echo "set ADAMAS_BIN to an executable Adamas compiler" >&2
  exit 2
fi
if [[ -z "$CRYSTAL_BIN" || ! -x "$CRYSTAL_BIN" ]]; then
  echo "set CRYSTAL_BIN to an installed Crystal compiler" >&2
  exit 2
fi

if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
else
  CRYSTAL_STDLIB="$("$CRYSTAL_BIN" env CRYSTAL_PATH)"
fi
if [[ ! -d "${CRYSTAL_STDLIB%%:*}" ]]; then
  echo "Crystal stdlib path is not a directory: $CRYSTAL_STDLIB" >&2
  exit 2
fi

for fixture in "${FIXTURES[@]}"; do
  if [[ ! -f "$FIXTURE_DIR/$fixture" ]]; then
    echo "missing heredoc fixture: $FIXTURE_DIR/$fixture" >&2
    exit 2
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-heredoc-coverage.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
printf 'A\n' >"$WORK_DIR/expected.stdout"

fail_with_log() {
  local message="$1"
  local log="$2"
  echo "$message" >&2
  if [[ -s "$log" ]]; then
    cat "$log" >&2
  fi
  exit 1
}

compile_and_check() {
  local mode="$1"
  local fixture="$2"
  local source="$FIXTURE_DIR/$fixture"
  local stem="${fixture%.cr}"
  local binary="$WORK_DIR/${mode}_${stem}"
  local compile_log="$WORK_DIR/${mode}_${stem}.compile.log"
  local run_log="$WORK_DIR/${mode}_${stem}.run.log"
  local stdout="$WORK_DIR/${mode}_${stem}.stdout"
  local cache_dir="$WORK_DIR/${mode}_crystal_cache"

  mkdir -p "$cache_dir"
  case "$mode" in
    stock)
      if ! (
        cd "$WORK_DIR"
        env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
          "$SAFE_RUNNER" "$CRYSTAL_BIN" 180 8192 build --prelude=empty "$source" -o "$binary"
      ) >"$compile_log" 2>&1; then
        fail_with_log "stock Crystal compile failed: $fixture" "$compile_log"
      fi
      ;;
    lazy)
      if ! (
        cd "$WORK_DIR"
        env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
          "$SAFE_RUNNER" "$ADAMAS_BIN" 180 8192 --prelude=empty "$source" -o "$binary"
      ) >"$compile_log" 2>&1; then
        fail_with_log "Adamas lazy-HIR compile failed: $fixture" "$compile_log"
      fi
      ;;
    eager)
      if ! (
        cd "$WORK_DIR"
        env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" ADAMAS_EAGER_HIR=1 \
          "$SAFE_RUNNER" "$ADAMAS_BIN" 180 8192 --prelude=empty "$source" -o "$binary"
      ) >"$compile_log" 2>&1; then
        fail_with_log "Adamas eager-HIR compile failed: $fixture" "$compile_log"
      fi
      ;;
    *)
      echo "unknown compiler mode: $mode" >&2
      exit 2
      ;;
  esac

  if ! (
    cd "$WORK_DIR"
    env RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 10 512
  ) >"$stdout" 2>"$run_log"; then
    fail_with_log "$mode executable failed: $fixture" "$run_log"
  fi
  if ! cmp -s "$WORK_DIR/expected.stdout" "$stdout"; then
    echo "$mode stdout mismatch: $fixture (expected exactly A\\n)" >&2
    if [[ -s "$stdout" ]]; then
      od -An -tx1 "$stdout" >&2
    else
      echo "<empty>" >&2
    fi
    exit 1
  fi

  echo "PASS $mode $fixture"
}

# Establish the stock Crystal behavior for every fixture before running either
# Adamas HIR mode.
for fixture in "${FIXTURES[@]}"; do
  compile_and_check stock "$fixture"
done

unset ADAMAS_EAGER_HIR
for fixture in "${FIXTURES[@]}"; do
  compile_and_check lazy "$fixture"
done

for fixture in "${FIXTURES[@]}"; do
  compile_and_check eager "$fixture"
done

echo "PASS all six heredoc source-ownership fixtures in stock, lazy, and eager modes"
