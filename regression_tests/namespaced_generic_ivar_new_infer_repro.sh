#!/usr/bin/env bash
# Regression: `@heap = Heap(T).new` inside `Ns::Box::Timers(T)` must infer the
# owner-namespace type `Ns::Heap(T)`. Ivar inference and `.new` return
# inference resolved the bare name, registering a phantom top-level
# `Heap(Int32)` (ivar typed `Heap(Int32) | Ns::Heap(Int32)`). In S2 the phantom
# union reached PointerPairingHeap#hash and `STDERR.flush` failed to lower.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/namespaced_generic_ivar_new_infer_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

status=0

cat >"$WORK_DIR/n1.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Ns::Heap(T)
  def initialize; end
  def code : Int32
    7
  end
end
struct Ns::Box::Timers(T)
  def initialize
    @heap = Heap(T).new
  end
  def code : Int32
    @heap.code
  end
end
t = Ns::Box::Timers(Int32).new
LibC.exit(t.code)
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/n1.cr" --no-prelude --emit hir -o "$WORK_DIR/n1" >"$WORK_DIR/n1.build.log" 2>&1; then
  echo "FAIL[n1]: compile failed" >&2
  tail -20 "$WORK_DIR/n1.build.log" >&2
  status=1
else
  if grep -nE '(^|[^:])Heap\(Int32\)' "$WORK_DIR/n1.hir" >&2; then
    echo "FAIL[n1]: phantom unqualified Heap(Int32) type registered" >&2
    status=1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/n1" 5 512 >"$WORK_DIR/n1.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 7\]' "$WORK_DIR/n1.run.log"; then
    echo "FAIL[n1]: expected exit 7" >&2
    cat "$WORK_DIR/n1.run.log" >&2
    status=1
  fi
fi

if [ "$status" -ne 0 ]; then
  echo "FAIL: namespaced generic ivar .new inferred a phantom top-level type" >&2
  exit 1
fi
echo "PASS: namespaced generic ivar .new resolves against the owner namespace"
