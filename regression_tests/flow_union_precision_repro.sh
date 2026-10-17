#!/usr/bin/env bash
# Flow joins must not admit unused variants from previously registered unions.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${COMPILER:-$ROOT_DIR/bin/adamas}}"
CASE="${2:-all}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$RUN_SAFE" && -x "$COMPILER" && -x "$ORIGINAL" ]] || {
  echo "usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal CRYSTAL_PATH=/path/to/stdlib $0 /path/to/adamas [all|plain|seeded|case|rescue|nil_guard]" >&2
  exit 2
}
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flow-union-precision.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT
DEFAULT_LINK_FLAGS=""
[[ "$(uname -s)" != Darwin ]] || DEFAULT_LINK_FLAGS=-fuse-ld=/usr/bin/ld
ORIGINAL_LINK_FLAGS="${ORIGINAL_LINK_FLAGS-$DEFAULT_LINK_FLAGS}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS-$DEFAULT_LINK_FLAGS}"
cat >"$WORK_DIR/seeded.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end
abstract class BaseType
end
class PrimitiveType < BaseType
end
class MethodInfo
  getter return_annotation : Int32?
  def initialize(@return_annotation : Int32?)
  end
end
class ProbeContext
  getter nil_type : PrimitiveType
  def initialize
    @nil_type = PrimitiveType.new
  end
  def union_of(types : Array(BaseType)) : BaseType
    types.first
  end
end
class Engine
  def initialize(@context : ProbeContext)
  end
  def lookup_type_by_name(name : Int32) : BaseType?
    PrimitiveType.new
  end
  def infer_navigation(method : MethodInfo?) : BaseType
    if method
      result_type = if return_annotation = method.return_annotation
        lookup_type_by_name(return_annotation) || @context.nil_type
      else
        @context.nil_type
      end
      @context.union_of([result_type, @context.nil_type])
    else
      @context.nil_type
    end
  end
end
# Materialize a nullable union before lowering the non-null if expression.
def seed_nullable_type(value : BaseType | PrimitiveType | Nil) : BaseType | PrimitiveType | Nil
  value
end
seed_nullable_type(nil)

engine = Engine.new(ProbeContext.new)
engine.infer_navigation(MethodInfo.new(1))
Probe.putchar(65)
engine.infer_navigation(MethodInfo.new(nil))
Probe.putchar(66)
engine.infer_navigation(nil)
Probe.putchar(67)
CRYSTAL
python3 - "$WORK_DIR" <<'PYTHON'
from pathlib import Path
import sys
work = Path(sys.argv[1])
source = (work / 'seeded.cr').read_text()
start = source.index('# Materialize a nullable union')
end = source.index('engine = Engine.new', start)
(work / 'plain.cr').write_text(source[:start] + source[end:])
old = """      result_type = if return_annotation = method.return_annotation
        lookup_type_by_name(return_annotation) || @context.nil_type
      else
        @context.nil_type
      end"""
assert source.count(old) == 1
case = """      result_type = case return_annotation = method.return_annotation
      when Int32
        lookup_type_by_name(return_annotation) || @context.nil_type
      else
        @context.nil_type
      end"""
rescue = """      result_type = begin
        lookup_type_by_name(1) || @context.nil_type
      rescue
        @context.nil_type
      end"""
nil_guard = old.replace('      else\n        @context.nil_type', '      else\n        nil')
for name, replacement in [('case', case), ('rescue', rescue), ('nil_guard', nil_guard)]:
    (work / (name + '.cr')).write_text(source.replace(old, replacement))
PYTHON
printf 'ABC' >"$WORK_DIR/expected"

run_case() {
  local name="$1" stage compiler binary status
  for stage in original candidate; do
    compiler="$COMPILER"
    [[ "$stage" != original ]] || compiler="$ORIGINAL"
    binary="$WORK_DIR/$name.$stage.bin"
    local -a command
    if [[ "$stage" == original ]]; then
      command=("$compiler" build "$WORK_DIR/$name.cr" -o "$binary" --no-debug)
      [[ -z "$ORIGINAL_LINK_FLAGS" ]] || command+=("--link-flags=$ORIGINAL_LINK_FLAGS")
    else
      command=("$compiler" "$WORK_DIR/$name.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$binary")
    fi
    status=0
    env "CRYSTAL_CACHE_DIR=$WORK_DIR/$stage.cache" \
      "$RUN_SAFE" "${command[0]}" 120 4096 "${command[@]:1}" \
      >"$WORK_DIR/$name.$stage.build.log" 2>&1 || status=$?
    rm -rf "$WORK_DIR/$stage.cache"
    if [[ "$name" == nil_guard ]]; then
      if [[ "$status" != 1 ]] || ! grep -Eq 'no overload matches ProbeContext#union_of|Error: expected argument #1.*Array' "$WORK_DIR/$name.$stage.build.log"; then
        echo "FAIL: $stage must reject a real Nil arm at Array(BaseType), status=$status" >&2
        tail -35 "$WORK_DIR/$name.$stage.build.log" >&2
        return 1
      fi
      continue
    fi
    if [[ "$status" != 0 ]]; then
      tail -35 "$WORK_DIR/$name.$stage.build.log" >&2
      return 1
    fi
    if ! env RUN_SAFE_PASSTHROUGH_STDIO=1 \
      "$RUN_SAFE" "$binary" 10 512 >"$WORK_DIR/$name.$stage.stdout" \
      2>"$WORK_DIR/$name.$stage.run.log"; then
      tail -35 "$WORK_DIR/$name.$stage.run.log" >&2
      return 1
    fi
    cmp "$WORK_DIR/expected" "$WORK_DIR/$name.$stage.stdout"
  done
  printf 'PASS: %s flow union precision\n' "$name"
}
case "$CASE" in
  all) run_case plain; run_case seeded; run_case case; run_case rescue; run_case nil_guard ;;
  plain|seeded|case|rescue|nil_guard) run_case "$CASE" ;;
  *) echo "unknown case: $CASE" >&2; exit 2 ;;
esac
