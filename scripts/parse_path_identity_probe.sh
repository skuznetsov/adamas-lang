#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler> [source]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SOURCE="${2:-$ROOT_DIR/src/adamas.cr}"
TMP_DIR="$(mktemp -d "$ROOT_DIR/tmp/parse-path-identity.XXXXXX")"
LOG="$TMP_DIR/parse.log"
OUT="$TMP_DIR/out"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

set +e
ADAMAS_STOP_AFTER_PARSE=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 4096 \
  "$SOURCE" --no-prelude --verbose -o "$OUT" >"$LOG" 2>&1
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "FAIL: stop-after-parse compile failed with rc=$rc" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

loading_count="$(grep -c '^  Loading: ' "$LOG" || true)"
if [[ "$loading_count" -le 0 ]]; then
  echo "FAIL: compiler verbose output did not contain Loading lines" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

canonical_count="$(
  grep '^  Loading: ' "$LOG" |
    sed 's/^  Loading: //' |
    perl -MCwd=abs_path -ne 'chomp; $p = abs_path($_) || $_; $seen{$p}=1; END { print scalar(keys %seen), "\n" }'
)"

echo "raw=$loading_count canonical=$canonical_count source=$SOURCE"

if [[ "$loading_count" != "$canonical_count" ]]; then
  echo "DUPLICATE_PATH_IDENTITY raw=$loading_count canonical=$canonical_count"
  grep '^  Loading: ' "$LOG" |
    sed 's/^  Loading: //' |
    perl -MCwd=abs_path -ne '
      chomp;
      $p = abs_path($_) || $_;
      push @{$raw{$p}}, $_;
      END {
        $groups = 0;
        for $p (sort keys %raw) {
          next unless @{$raw{$p}} > 1;
          $groups++;
          last if $groups > 12;
          print "canonical=$p\n";
          for $r (@{$raw{$p}}) { print "  raw=$r\n"; }
        }
      }
    '
  exit 3
fi

echo "PASS parse_path_identity"
