#!/usr/bin/env bash
# A generated allocator must carry the selected initializer's source admission,
# so an unrelated explicit new rejection cannot mask a valid positional call.
set -euo pipefail
ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${COMPILER:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
if [[ ! -x "$SAFE" || ! -x "$CANDIDATE" || ! -x "$ORIGINAL" ]]; then
  echo "ERROR: set COMPILER and ORIGINAL_CRYSTAL_BIN to executable paths" >&2
  exit 2
fi
if [[ -z "${CRYSTAL_PATH:-}" && -d "$ROOT_DIR/../crystal/src" ]]; then
  export CRYSTAL_PATH="$ROOT_DIR/../crystal/src"
fi
if [[ -n "${LLVM_ROOT:-}" ]]; then
  export PATH="$LLVM_ROOT/bin:$PATH"
  export CRYSTAL_LIBRARY_PATH="$LLVM_ROOT/lib${CRYSTAL_LIBRARY_PATH:+:$CRYSTAL_LIBRARY_PATH}"
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/generated-allocator-source.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK/original.cache" "$WORK/candidate.cache"
  if [[ "$status" == 0 && "${KEEP_ARTIFACTS:-0}" != 1 ]]; then
    rm -rf "$WORK"
  else
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  fi
}
trap cleanup EXIT
cat >"$WORK/control.cr" <<'CRYSTAL'
require "set"
lib AllocatorGuardC
  fun putchar(value : Int32) : Int32
end
capacity = Set(String).new(4)
AllocatorGuardC.putchar(65) if capacity.empty?
capacity.add("root")
AllocatorGuardC.putchar(66) if capacity.includes?("root")
class AllocatorGuardMixed
  getter value : Int32
  def initialize(@value : Int32)
  end
  def self.new(value : String)
    67
  end
end
AllocatorGuardC.putchar(AllocatorGuardMixed.new(68).value)
AllocatorGuardC.putchar(AllocatorGuardMixed.new("explicit"))
class AllocatorGuardExplicitFirst
  def initialize(@value : Int32)
  end
  def self.new(value : Int32)
    value + 1
  end
end
AllocatorGuardC.putchar(AllocatorGuardExplicitFirst.new(68))
AllocatorGuardC.putchar(10)
CRYSTAL
cat >"$WORK/wrong_scalar.cr" <<'CRYSTAL'
class AllocatorGuardBothReject
  def initialize(value : Int32)
  end
  def self.new(value : Indexable(String))
    7
  end
end
AllocatorGuardBothReject.new(true)
CRYSTAL
printf 'ABDCE\n' >"$WORK/control.expected"
cat >"$WORK/run_program" <<'SH'
#!/usr/bin/env bash
exec "$1" 2>"$2"
SH
chmod +x "$WORK/run_program"
compile() {
  local stage="$1" name="$2"
  local -a args
  if [[ "$stage" == original ]]; then
    args=("$ORIGINAL" 120 8192 build "$WORK/$name.cr" --single-module --no-debug)
    if [[ "$(uname -s)" == Darwin ]]; then args+=(--link-flags=-fuse-ld=/usr/bin/ld); fi
  else
    args=("$CANDIDATE" 120 8192 "$WORK/$name.cr" --no-debug --no-ast-cache --no-llvm-cache)
  fi
  CRYSTAL_CACHE_DIR="$WORK/$stage.cache" "$SAFE" "${args[@]}" -o "$WORK/$stage.$name.bin" >"$WORK/$stage.$name.compile.log" 2>&1
}
check() {
  local stage="$1" name="$2" status=0
  if [[ "$name" == wrong_scalar ]]; then
    compile "$stage" "$name" || status=$?
    if [[ "$status" != 1 || -e "$WORK/$stage.$name.bin" ]]; then
      cat "$WORK/$stage.$name.compile.log" >&2
      printf 'FAIL %s: incompatible source argument requires rc1/no executable, got %s\n' "$stage" "$status" >&2
      return 1
    fi
    rg -q 'Bool' "$WORK/$stage.$name.compile.log"
    rg -q '(Int32|Indexable|initializer source restriction)' "$WORK/$stage.$name.compile.log"
  else
    if ! compile "$stage" "$name"; then cat "$WORK/$stage.$name.compile.log" >&2; return 1; fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 10 512 "$WORK/$stage.$name.bin" "$WORK/$stage.$name.stderr" >"$WORK/$stage.$name.stdout" 2>"$WORK/$stage.$name.run.log"
    test ! -s "$WORK/$stage.$name.stderr"
    cmp "$WORK/$name.expected" "$WORK/$stage.$name.stdout"
  fi
}
for name in control wrong_scalar; do check original "$name"; done
for name in control wrong_scalar; do check candidate "$name"; done
printf 'PASS: generated allocator source admission and retained generic rejection\n'
