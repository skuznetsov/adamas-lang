#!/usr/bin/env bash
set -euo pipefail

compiler="${1:-bin/crystal_v2}"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/crystalv2-source-extern.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

src="$workdir/source_extern.cr"
out="$workdir/out"
stdout_file="$workdir/stdout.log"
stderr_file="$workdir/stderr.log"

cat > "$src" <<'CR'
lib LibTiny
  alias SizeT = UInt64
  fun tiny_open = "open"(path : UInt8*, flags : Int32, ...) : Int32
  fun tiny_errno : Int32
end
CR

"$compiler" "$src" --no-prelude --no-link --emit hir -o "$out" >"$stdout_file" 2>"$stderr_file"

if grep -q "STUB CALLED" "$stderr_file"; then
  echo "unexpected abort stub while registering source-backed extern signatures" >&2
  cat "$stderr_file" >&2
  exit 1
fi

if ! grep -q "lib register done" "$stderr_file"; then
  echo "expected lib registration trace was not observed" >&2
  cat "$stderr_file" >&2
  exit 1
fi

echo "p2_source_extern_signature_no_prelude_ok"
