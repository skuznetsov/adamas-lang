#!/usr/bin/env bash
# Qualify selected bare class-method return types when the call has a literal
# block. HIR cold-cache coverage lives in selected_class_block_result_inference_spec.cr.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -n "$ORIGINAL" && -x "$ORIGINAL" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "candidate, installed Crystal, SAFE runner, or Crystal stdlib is unavailable" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/selected-class-block-result.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache.*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
end

class BlockGlobalResult
end

class BlockNoResult
end

class BlockOnlyResult
end

class BlockClassResult
end

class BlockInstanceResult
end

class SelectedClassBlockProbe
  # Deliberately shadows the global name used by the selected return contract.
  class BlockGlobalResult
  end

  def self.emit(value : ::BlockGlobalResult)
    LibC.putchar(71)
  end

  def self.emit(value : SelectedClassBlockProbe::BlockGlobalResult)
    LibC.putchar(88)
  end

  def self.emit(value : BlockNoResult)
    LibC.putchar(78)
  end

  def self.emit(value : BlockOnlyResult)
    LibC.putchar(66)
  end

  def self.emit(value : BlockClassResult)
    LibC.putchar(67)
  end

  def self.emit(value : BlockInstanceResult)
    LibC.putchar(73)
  end

  def self.global_value : ::BlockGlobalResult
    ::BlockGlobalResult.new
  end

  def self.yield_once(&block : -> ::BlockGlobalResult) : ::BlockGlobalResult
    yield
  end

  def self.yield_twice(&block : -> ::BlockGlobalResult) : ::BlockGlobalResult
    yield_once { yield }
  end

  def self.one_layer
    yield_once { global_value }
  end

  def self.two_layers
    yield_twice { global_value }
  end

  def self.choice : BlockNoResult
    BlockNoResult.new
  end

  def self.choice(&block : -> BlockOnlyResult) : BlockOnlyResult
    yield
  end

  def self.class_or_instance(&block : -> BlockClassResult) : BlockClassResult
    yield
  end

  def class_or_instance(&block : -> BlockInstanceResult) : BlockInstanceResult
    yield
  end

  def self.run
    emit(one_layer)
    emit(two_layers)
    emit(choice)
    emit(choice { BlockOnlyResult.new })
    emit(class_or_instance { BlockClassResult.new })
    emit(yield_once { global_value })
    LibC.putchar(10)
  end
end

SelectedClassBlockProbe.run
CRYSTAL
printf 'GGNBCG\n' >"$WORK_DIR/positive.expected"

cat >"$WORK_DIR/reject_wrong_arity.cr" <<'CRYSTAL'
class SelectedClassBlockWrongArity
  def self.needs_argument(value : Int32, &block : -> Int32) : Int32
    yield
  end

  def self.run
    needs_argument { 65 }
  end
end

SelectedClassBlockWrongArity.run
CRYSTAL

cat >"$WORK_DIR/reject_block_result.cr" <<'CRYSTAL'
class SelectedClassBlockWrongResult
end

class SelectedClassBlockResultMismatch
  def self.needs_global(&block : -> ::SelectedClassBlockWrongResult) : ::SelectedClassBlockWrongResult
    yield
  end

  def self.run
    needs_global { 65 }
  end
end

SelectedClassBlockResultMismatch.run
CRYSTAL

ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)

compile_case() {
  local stage="$1" name="$2" status=0
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$ORIGINAL" 180 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    command=("$COMPILER" 180 8192 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$name" ADAMAS_LLVM_CACHE=0 \
    "$SAFE_RUNNER" "${command[@]}" "$WORK_DIR/$name.cr" -o "$WORK_DIR/$stage.$name.bin" \
    >"$WORK_DIR/$stage.$name.compile.log" 2>&1 || status=$?
  return "$status"
}

check_rejection() {
  local stage="$1" name="$2" expected_name="$3" expected_type="${4:-}"
  local status=0
  compile_case "$stage" "$name" || status=$?
  if [[ "$status" != 1 || -e "$WORK_DIR/$stage.$name.bin" ]]; then
    cat "$WORK_DIR/$stage.$name.compile.log" >&2
    echo "FAIL[$stage/$name]: expected semantic rejection without an executable" >&2
    return 1
  fi
  python3 - "$WORK_DIR/$stage.$name.compile.log" "$expected_name" "$expected_type" <<'PY_REJECT'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace").lower()
assert "error" in text, text
assert sys.argv[2].lower() in text, text
if sys.argv[3]:
    assert sys.argv[3].lower() in text, text
assert "syntax error" not in text and "parser errors" not in text, text
assert "internal compiler error" not in text and "unhandled exception" not in text, text
PY_REJECT
}

for stage in original candidate; do
  compile_case "$stage" positive || {
    cat "$WORK_DIR/$stage.positive.compile.log" >&2
    exit 1
  }
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/$stage.positive.bin" 10 512 \
    >"$WORK_DIR/$stage.stdout" 2>"$WORK_DIR/$stage.run.log" || {
      cat "$WORK_DIR/$stage.run.log" >&2
      exit 1
    }
  diff -u "$WORK_DIR/positive.expected" "$WORK_DIR/$stage.stdout"
  check_rejection "$stage" reject_wrong_arity needs_argument
  check_rejection "$stage" reject_block_result needs_global SelectedClassBlockWrongResult
  echo "PASS[$stage]: selected block results, overload identity, arity, and block-result contract"
done

diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"
