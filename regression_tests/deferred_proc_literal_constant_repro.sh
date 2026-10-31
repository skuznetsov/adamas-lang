#!/usr/bin/env bash
# A Proc literal constant must publish a real closure/function initializer.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/deferred-proc-literal-constant.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

[[ -x "$SAFE" && -x "$ORIGINAL" && -f "$STDLIB/empty.cr" ]] || exit 2
if [[ "${ORIGINAL_ONLY:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  echo 'ERROR: candidate compiler is unavailable' >&2
  exit 2
fi

cat > "$WORK/literals.cr" <<'CRYSTAL'
@[Link("c")]
lib DeferredProcLiteralOutput
  fun putchar(value : Int32) : Int32
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end

module DeferredProcLiterals
  NOARG = -> { 65 }
  TYPED = ->(value : Int32) { value }
end

module DeferredProcSibling
  NOARG = -> { 66 }
end

class DeferredProcClass
  VALUE = -> { 68 }
end

ROOT_PROC = -> { 69 }
DeferredProcLiteralOutput.putchar(DeferredProcLiterals::NOARG.call)
DeferredProcLiteralOutput.putchar(DeferredProcLiterals::TYPED.call(67))
DeferredProcLiteralOutput.putchar(DeferredProcSibling::NOARG.call)
DeferredProcLiteralOutput.putchar(DeferredProcClass::VALUE.call)
DeferredProcLiteralOutput.putchar(ROOT_PROC.call)
CRYSTAL
sed 's/TYPED.call(67)/TYPED.call(true)/' "$WORK/literals.cr" > "$WORK/wrong_argument.cr"

run_case() {
  local mode="$1" probe="$2" status=0
  local output="$WORK/$mode.$probe"
  if [[ "$mode" == stock ]]; then
    env CRYSTAL_PATH="$STDLIB" CRYSTAL_CACHE_DIR="$WORK/cache.$mode.$probe" \
      "$SAFE" "$ORIGINAL" 180 8192 build "$WORK/$probe.cr" \
      --prelude=empty --no-debug --link-flags="$LINK_FLAGS" -o "$output" \
      > "$output.build.log" 2>&1 || status=$?
  else
    local mode_env=(CRYSTAL_PATH="$STDLIB" ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS")
    [[ "$mode" == eager ]] && mode_env+=(ADAMAS_EAGER_MONO=1)
    env -u ADAMAS_EAGER_MONO "${mode_env[@]}" \
      "$SAFE" "$CANDIDATE" 180 8192 "$WORK/$probe.cr" \
      --prelude=empty --no-debug --no-ast-cache --no-llvm-cache \
      -o "$output" > "$output.build.log" 2>&1 || status=$?
  fi
  if [[ "$probe" == wrong_argument ]]; then
    if [[ "$status" != 1 ]] || ! grep -q Bool "$output.build.log" ||
       ! grep -q Int32 "$output.build.log" ||
       ! grep -Eq 'no overload matches|expected|must be' "$output.build.log"; then
      cat "$output.build.log" >&2
      printf 'FAIL %s/%s: expected source rejection, got %s\n' "$mode" "$probe" "$status" >&2
      exit 1
    fi
  else
    if [[ "$status" != 0 ]]; then
      cat "$output.build.log" >&2
      exit 1
    fi
    env RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 \
      > "$output.stdout" 2> "$output.run.log"
    printf ACBDE > "$output.expected"
    cmp "$output.expected" "$output.stdout"
  fi
  printf 'PASS %s/%s\n' "$mode" "$probe"
}

for probe in literals wrong_argument; do
  run_case stock "$probe"
done
if [[ "${ORIGINAL_ONLY:-0}" != 1 ]]; then
  for mode in lazy eager; do
    for probe in literals wrong_argument; do
      run_case "$mode" "$probe"
    done
  done
fi
