#!/usr/bin/env bash
# A source .new is an ordinary class method, including an empty splat result.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
CANDIDATE="${1:-$ROOT/bin/adamas}"
[[ -x "$SAFE" && -x "$ORIGINAL" && -x "$CANDIDATE" ]] || exit 2
WORK="$(mktemp -d "${TMPDIR:-/tmp}/source-class-new-return.XXXXXX")"
cleanup() {
  local rc=$?
  rm -rf "$WORK/original.cache" "$WORK/candidate.cache"
  if [[ "$rc" == 0 ]]; then
    rm -rf "$WORK"
  else
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  fi
}
trap cleanup EXIT

cat >"$WORK/run_program" <<'RUNNER'
#!/usr/bin/env bash
exec "$1" 2>"$2"
RUNNER
chmod +x "$WORK/run_program"

cat >"$WORK/source_new.cr" <<'SOURCE_NEW'
lib LibC
  fun putchar(c : Int32) : Int32
end

class SourceNewControlScalar
  def self.new
    7
  end
end

class SourceNewControlDefault
  def self.new(value = 9)
    value
  end
end

class SourceNewControlVariadic
  def self.new(*args)
    args
  end
end

class SourceNewControlAllocated
  def initialize(@value : Int32 = 11)
  end

  def value
    @value
  end
end

LibC.putchar(Tuple.new.is_a?(Tuple()) ? 69 : 71)
LibC.putchar(Tuple.new().is_a?(Tuple()) ? 69 : 71)
LibC.putchar(SourceNewControlScalar.new.is_a?(Int32) ? 69 : 71)
LibC.putchar(SourceNewControlScalar.new().is_a?(Int32) ? 69 : 71)
LibC.putchar(SourceNewControlScalar.new == 7 ? 69 : 71)
LibC.putchar(SourceNewControlScalar.new() == 7 ? 69 : 71)
LibC.putchar(SourceNewControlDefault.new == 9 ? 69 : 71)
LibC.putchar(SourceNewControlDefault.new() == 9 ? 69 : 71)
LibC.putchar(SourceNewControlVariadic.new.is_a?(Tuple()) ? 69 : 71)
LibC.putchar(SourceNewControlVariadic.new().is_a?(Tuple()) ? 69 : 71)
LibC.putchar(SourceNewControlVariadic.new(1, "x").is_a?(Tuple(Int32, String)) ? 69 : 71)
LibC.putchar(SourceNewControlVariadic.new(1, "x")[0] == 1 ? 69 : 71)
LibC.putchar(SourceNewControlAllocated.new.value == 11 ? 69 : 71)
LibC.putchar(SourceNewControlAllocated.new().value == 11 ? 69 : 71)
LibC.putchar(10)
SOURCE_NEW

printf 'EEEEEEEEEEEEEE\n' >"$WORK/expected.stdout"
for stage in original candidate; do
  if [[ "$stage" == original ]]; then
    args=("$ORIGINAL" 120 8192 build "$WORK/source_new.cr" --no-debug)
    if [[ "$(uname -s)" == Darwin ]]; then args+=(--link-flags=-fuse-ld=/usr/bin/ld); fi
  else
    args=("$CANDIDATE" 120 8192 "$WORK/source_new.cr" --no-debug --no-ast-cache --no-llvm-cache)
  fi
  if ! CRYSTAL_CACHE_DIR="$WORK/$stage.cache" "$SAFE" "${args[@]}" -o "$WORK/$stage.bin" >"$WORK/$stage.compile.log" 2>&1; then
    tail -45 "$WORK/$stage.compile.log" >&2
    exit 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 10 512 "$WORK/$stage.bin" "$WORK/$stage.stderr" >"$WORK/$stage.stdout" 2>"$WORK/$stage.run.log"
  test ! -s "$WORK/$stage.stderr"
  cmp "$WORK/expected.stdout" "$WORK/$stage.stdout"
done
printf 'PASS: source new result types, values, defaults and splats; generated allocator controls\n'
