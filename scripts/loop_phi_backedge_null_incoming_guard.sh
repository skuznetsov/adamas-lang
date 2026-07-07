#!/usr/bin/env bash
# L10-β structural guard: loop-header/exit phis must cover every real
# predecessor — a phi missing an incoming makes the backend fabricate a
# null/zero incoming ("[null, %bbN]" in the emitted .ll).
#
# Compiles a no-prelude reducer that historically produced 2 fabricated null
# incomings (missing backedge self-incoming + detached block-body `next`/
# `break` wiring dead edges into the enclosing while) and fails if ANY
# "[null, %bb" incoming appears in the run function's module.
#
# Usage: scripts/loop_phi_backedge_null_incoming_guard.sh [path-to-compiler]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loop_phi_guard.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/loop_phi_backedge.cr"
cat >"$SRC" <<'CR'
lib GuardLibC
  fun exit(code : Int32) : NoReturn
end

class Name
  def initialize(@v : Int32)
  end

  def v : Int32
    @v
  end
end

def make_name(v : Int32) : Name
  Name.new(v)
end

def lookup(p : Int32) : Name?
  p == 3 ? make_name(111) : nil
end

def seen_add(p : Int32) : Bool
  p < 100
end

def advance(p : Int32) : Int32?
  p >= 5 ? nil : p + 1
end

def advance2(p : Int32) : Int32?
  nil
end

def each_k(n : Int32)
  j = 0
  while j < n
    yield j
    j += 1
  end
end

def run(start : Int32) : Int32
  x : Name? = nil
  probe : Int32? = start
  while probe
    p = probe.not_nil!
    break unless seen_add(p)
    if cand = lookup(p)
      ok = true
      acc = 0
      each_k(3) do |k|
        next if k == 1
        if k == 2 && p == 999
          ok = false
          break
        end
        acc += k
      end
      if ok && p != 999
        x = cand
        break
      end
    end
    probe = advance(p) || advance2(p)
  end
  unless x
    x = make_name(777)
  end
  resolved = x.not_nil!
  resolved.v
end

GuardLibC.exit(run(1) == 111 && run(4) == 777 ? 0 : 1)
CR

"$COMPILER" "$SRC" --no-prelude --emit llvm-ir -o "$TMP_DIR/loop_phi_backedge" >/dev/null 2>&1

LL="$TMP_DIR/loop_phi_backedge.ll"
if [[ ! -f "$LL" ]]; then
  echo "[loop-phi-guard] FAIL: compiler did not produce $LL" >&2
  exit 2
fi

count=$(grep -c '\[null, %bb' "$LL" || true)
if [[ "$count" -ne 0 ]]; then
  echo "[loop-phi-guard] FAIL: $count fabricated null phi incoming(s):" >&2
  grep -n '\[null, %bb' "$LL" | head -10 >&2
  exit 1
fi

echo "[loop-phi-guard] PASS: no fabricated null phi incomings"
