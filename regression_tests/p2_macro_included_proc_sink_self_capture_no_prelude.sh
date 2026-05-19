#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="$1"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cv2_macro_included_proc_sink.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/repro.cr" <<'CR'
module M
  module Node
    macro included
      def marker : Int32
        1
      end
    end
  end
end

struct Op
  include M::Node
end
CR

log="$tmpdir/repro.log"
out="$tmpdir/repro"

"$ROOT_DIR/scripts/run_safe.sh" "$compiler" 30 1024 \
  "$tmpdir/repro.cr" --no-prelude --emit llvm-ir --no-link -o "$out" \
  >"$log" 2>&1

if [[ ! -s "$out.ll" ]]; then
  echo "macro included proc sink guard did not emit LLVM IR" >&2
  tail -120 "$log" >&2 || true
  exit 1
fi

if grep -Eq 'Segmentation fault|EXC_BAD_ACCESS|\\[CRASH\\]' "$log"; then
  echo "macro included proc sink guard saw a crash marker" >&2
  tail -120 "$log" >&2 || true
  exit 1
fi

echo "p2_macro_included_proc_sink_self_capture_no_prelude_ok"
