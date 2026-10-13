#!/usr/bin/env bash
# `def self.new` + `def initialize` declared inside a `{% begin %}` macro body. A stage2
# compiler (built by stage1) returned 1 instead of 41: a nil `parameter_provenance` compared
# equal to `ParameterSliceProvenance::SourceBacked`, so parameter annotations were read from
# foreign source spans and the wrong allocator was chosen. Stage1 passes; run this with a
# stage2 binary to guard the bootstrap (see nil_enum_equality_fold_repro.sh for the root).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_begin_self_new_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Fb
  @x : Int32
  {% begin %}
  def self.new(a : Int32) : self
    new(a, 40)
  end
  def initialize(a : Int32, b : Int32)
    @x = a + b
  end
  {% end %}
  def x; @x; end
end
LibC.exit(Fb.new(1).x)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '\[EXIT: 41\]' "$WORK_DIR/run.log"; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo macro_begin_self_new_repro_ok
