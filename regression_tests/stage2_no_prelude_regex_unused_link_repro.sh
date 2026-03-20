#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

compiler="$1"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/stage2_no_prelude_regex_unused_link.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

src="$workdir/repro.cr"
out_bin="$workdir/repro_bin"
stdout_file="$workdir/stdout.txt"
stderr_file="$workdir/stderr.txt"

cat >"$src" <<'CR'
1
CR

set +e
"$compiler" "$src" --no-prelude -o "$out_bin" >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [[ $status -eq 0 ]]; then
  echo "not reproduced"
  exit 0
fi

if rg -q 'pcre2_[A-Za-z0-9_]*' "$stderr_file" && \
   rg -q 'Undefined symbols|undefined reference' "$stderr_file"; then
  echo "reproduced: unresolved PCRE2 symbols on no-prelude tiny-link"
  exit 1
fi

echo "inconclusive: unexpected status=$status" >&2
echo "--- stdout ---" >&2
cat "$stdout_file" >&2
echo "--- stderr ---" >&2
cat "$stderr_file" >&2
exit 2
