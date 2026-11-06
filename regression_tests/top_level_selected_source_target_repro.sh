#!/usr/bin/env bash
# A fast top-level call must emit the overload selected from source value kinds.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/top-level-source-target.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache-*
  if [[ "$status" == 0 && "${KEEP_TMP:-0}" != 1 ]]; then
    rm -rf -- "$WORK_DIR"
  else
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  fi
}
trap cleanup EXIT
[[ -x "$COMPILER" && -x "$ORIGINAL" && -x "$SAFE_RUNNER" ]]
export ADAMAS_LLVM_CACHE=0
original_link_flags="${ORIGINAL_CRYSTAL_LINK_FLAGS:-}"
if [[ "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
  original_link_flags="${original_link_flags:--fuse-ld=/usr/bin/ld}"
fi

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
@[Link("gc")]
lib TargetOutput
  fun putchar(value : Int32) : Int32
end
def choose(value : Int32.class) : Int32
  65
end
def choose(value : Int32) : Int32
  66
end
def reverse_choose(value : Int32) : Int32
  67
end
def reverse_choose(value : Int32.class) : Int32
  68
end
def through_yield(value)
  yield value
end
def passthrough_number(value)
  value
end
TargetOutput.putchar(choose(Int32))
TargetOutput.putchar(choose(1))
TargetOutput.putchar(reverse_choose(2))
TargetOutput.putchar(::reverse_choose(Int32))
TargetOutput.putchar(choose(through_yield(Int32) { |value| value }))
TargetOutput.putchar(passthrough_number(69))
TargetOutput.putchar(passthrough_number(70))
TargetOutput.putchar(10)
CRYSTAL
cat >"$WORK_DIR/negative.cr" <<'CRYSTAL'
def only_instance(value : Int32)
  value
end
only_instance(Int32)
CRYSTAL
printf 'ABCDAEF\n' >"$WORK_DIR/expected.stdout"

for phase in original candidate; do
  for test_case in positive negative; do
    cache="$WORK_DIR/cache-$phase-$test_case"
    mkdir "$cache"
    output="$WORK_DIR/$phase-$test_case"
    log="$output.build.log"
    if [[ "$phase" == original ]]; then
      args=(build --prelude=empty --no-debug --error-trace)
      [[ -z "$original_link_flags" ]] || args+=("--link-flags=$original_link_flags")
      args+=("$WORK_DIR/$test_case.cr")
      tool="$ORIGINAL"
    else
      args=("$WORK_DIR/$test_case.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
      tool="$COMPILER"
    fi
    status=0
    CRYSTAL_CACHE_DIR="$cache" "$SAFE_RUNNER" "$tool" 180 8192 \
      "${args[@]}" -o "$output" >"$log" 2>&1 || status=$?
    if [[ "$test_case" == negative ]]; then
      if [[ "$status" != 1 || -e "$output" ]] || ! grep -Eq 'no overload matches|expected argument.*Int32' "$log"; then
        cat "$log" >&2
        exit 1
      fi
      continue
    fi
    if [[ "$status" != 0 ]]; then
      cat "$log" >&2
      exit 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$output" 5 512 \
        >"$output.stdout" 2>"$output.run.log"; then
      cat "$output.run.log" >&2
      exit 1
    fi
    diff -u "$WORK_DIR/expected.stdout" "$output.stdout"
  done
done
echo 'PASS: top-level source selection owns the emitted overload'
