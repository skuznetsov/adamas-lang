#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURES="$ROOT/regression_tests/fixtures/enum_alias_member_path"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-enum-alias-member-path.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
export CRYSTAL_PATH="${CRYSTAL_PATH:-$(RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$CRYSTAL" 10 1024 env CRYSTAL_PATH)}"
link_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  link_flags+=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

for mode in stock lazy eager; do
  unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
  if [[ "$mode" == eager ]]; then
    export ADAMAS_EAGER_HIR=1 ADAMAS_EAGER_MONO=1
  fi

  for name in alias_member lexical_alias undefined_member shadowed_member; do
    source="$FIXTURES/$name.cr"
    output="$WORK/$mode.$name"
    log="$output.compile.log"
    status=0
    if [[ "$mode" == stock ]]; then
      "$SAFE" "$CRYSTAL" 120 8192 build "$source" --prelude=empty --no-debug \
        "${link_flags[@]}" -o "$output" >"$log" 2>&1 || status=$?
    else
      "$SAFE" "$ADAMAS" 120 8192 "$source" --no-prelude --no-debug --no-ast-cache \
        --no-llvm-cache -o "$output" >"$log" 2>&1 || status=$?
    fi
    case "$name" in
      undefined_member|shadowed_member)
        member=Missing
        [[ "$name" == shadowed_member ]] && member=Root
        if [[ "$status" != 1 ]] || ! rg -qiF "undefined constant Exposed::Options::$member" "$log"; then
          cat "$log" >&2
          printf 'FAIL %s %s (expected missing enum member)\n' "$mode" "$name" >&2
          exit 1
        fi
        printf 'PASS %s %s\n' "$mode" "$name"
        continue
        ;;
    esac
    if [[ "$status" != 0 ]]; then
      cat "$log" >&2
      printf 'FAIL %s %s (compile exit %s)\n' "$mode" "$name" "$status" >&2
      exit 1
    fi

    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 >"$output.stdout"
    expected=AA
    [[ "$name" == lexical_alias ]] && expected=LR
    printf '%s\n' "$expected" >"$output.expected"
    diff -u "$output.expected" "$output.stdout"
    printf 'PASS %s %s\n' "$mode" "$name"
  done
done
