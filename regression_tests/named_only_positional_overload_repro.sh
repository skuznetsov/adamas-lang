#!/usr/bin/env bash
# Regression: overload selection for calls that mix positional and named args.
# (1) Positional args spilled into named-only params (after `*`), so
#     `x.to_s(io, 16, upcase: true)` picked `to_s(base = 10, *, precision, upcase)`
#     (the io-less body), and io landed in `base`. In the stdlib this raised
#     "Invalid base", which broke String#dump/inspect and therefore `--emit hir`.
# (2) A param filled positionally was also accepted by name, so
#     `x.to_s(io, base: 16)` bound `base` twice on the io-less overload and dropped io.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named_only_positional_overload_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/no.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class Sink
  def initialize(@k : Int32); end
  def k; @k; end
end

struct Int32
  def ts(base : Int32 = 10, *, precision : Int32 = 1, upcase : Bool = false) : Int32
    -1
  end

  def ts(io : Sink, base : Int32 = 10, *, precision : Int32 = 1, upcase : Bool = false) : Int32
    io.k + base + (upcase ? 1 : 0)
  end
end

s = Sink.new(20)
code = 0
# Positional base plus a named-only arg must still reach the io overload.
code |= 1 unless 7.ts(s, 16, upcase: true) == 37
# Named base with positional io must not rebind base on the io-less overload.
code |= 2 unless 7.ts(s, base: 16, upcase: true) == 37
# Controls: no named args / named-only on the io-less overload.
code |= 4 unless 7.ts(s, 16) == 36
code |= 8 unless 7.ts(16, upcase: true) == -1
LibC.exit(code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/no.cr" --no-prelude -o "$WORK_DIR/no" >"$WORK_DIR/no.build.log" 2>&1; then
  echo "FAIL: compile failed" >&2
  tail -20 "$WORK_DIR/no.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/no" 5 512 >"$WORK_DIR/no.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/no.run.log"; then
  echo "FAIL: positional/named mixed call picked the wrong overload" >&2
  cat "$WORK_DIR/no.run.log" >&2
  exit 1
fi
echo "PASS: positional args do not fill named-only or named-bound params"
