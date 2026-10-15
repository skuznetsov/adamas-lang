#!/usr/bin/env bash
# Control-flow end tokens preserve statement separators without breaking expression continuations.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
}
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/control-flow-boundary.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
module StatementBoundaryResults
  extend self
  def conditional(flag : Bool) : Int64
    if flag
      return 1_i64
    end
    -42_i64
  end
  def inverse(flag : Bool) : Int64
    unless flag
      return 1_i64
    end
    -42_i64
  end
  def while_result : Int64
    while false
      break
    end
    -42_i64
  end
  def until_result : Int64
    until true
      break
    end
    -42_i64
  end
  def begin_result : Int64
    begin
      1_i64
    end
    -42_i64
  end
  def semicolon_result : Int64
    if false; 1_i64; end; -42_i64
  end
  def same_line : Int32
    if true
      44
    else
      0
    end - 2
  end
  def chained : Int32
    if true
      -42
    else
      0
    end
      .abs
  end
  def case_result : Int64
    case 0
    when 0
      1_i64
    end
    -42_i64
  end
end
C.exit(7) unless StatementBoundaryResults.conditional(false) == -42_i64
C.putchar(65)
C.exit(8) unless StatementBoundaryResults.inverse(true) == -42_i64
C.putchar(66)
C.exit(9) unless StatementBoundaryResults.while_result == -42_i64
C.putchar(67)
C.exit(10) unless StatementBoundaryResults.until_result == -42_i64
C.putchar(68)
C.exit(11) unless StatementBoundaryResults.begin_result == -42_i64
C.putchar(69)
C.exit(12) unless StatementBoundaryResults.semicolon_result == -42_i64
C.putchar(70)
C.exit(13) unless StatementBoundaryResults.same_line == 42
C.putchar(71)
C.exit(14) unless StatementBoundaryResults.chained == 42
C.putchar(72)
C.exit(15) unless StatementBoundaryResults.case_result == -42_i64
C.putchar(73)
CRYSTAL

for producer in original candidate; do
  bin="$WORK_DIR/$producer.bin"
  cache="$WORK_DIR/$producer.cache"
  mkdir -p "$cache"
  status=0
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/probe.cr" \
      -o "$bin" --no-debug --link-flags=-fuse-ld=/usr/bin/ld >"$WORK_DIR/$producer.build.log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache --no-debug -o "$bin" >"$WORK_DIR/$producer.build.log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]]; then
    cat "$WORK_DIR/$producer.build.log" >&2
    exit "$status"
  fi
  status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$bin" 15 512 >"$WORK_DIR/$producer.out" 2>"$WORK_DIR/$producer.run.log" || status=$?
  if [[ "$status" != 0 ]]; then
    cat "$WORK_DIR/$producer.run.log" >&2
    exit "$status"
  fi
  [[ "$(cat "$WORK_DIR/$producer.out")" == ABCDEFGHI ]] || {
    cat "$WORK_DIR/$producer.out" >&2
    exit 1
  }
done
cmp "$WORK_DIR/original.out" "$WORK_DIR/candidate.out"
echo 'PASS: control-flow expressions preserve statement boundaries'
