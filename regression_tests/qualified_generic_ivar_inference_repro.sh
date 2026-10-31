#!/usr/bin/env bash
# Qualified generic constructor receivers must publish the same ivar types as local names.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="${SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/qualified-generic-ivar.XXXXXX")"
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
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL" ]] || exit 2
ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
cat >"$WORK/positive.cr" <<'CRYSTAL'
lib QualifiedFieldOutput
  fun putchar(value : Int32) : Int32
end
module QualifiedFieldNative
  class Box(T)
    def initialize(@value : T)
    end
    def value : T
      @value
    end
  end
  class Holder(T)
    def initialize(value : T)
      @local = Box(T).new(value)
      @relative = QualifiedFieldNative::Box(T).new(value)
      @rooted = ::QualifiedFieldNative::Box(T).new(value)
    end
    def emit
      QualifiedFieldOutput.putchar(@local.value)
      QualifiedFieldOutput.putchar(@relative.value)
      QualifiedFieldOutput.putchar(@rooted.value)
      QualifiedFieldOutput.putchar(10)
    end
  end
end
QualifiedFieldNative::Holder(Int32).new(65).emit
CRYSTAL
cat >"$WORK/missing.cr" <<'CRYSTAL'
class MissingQualifiedFieldHolder
  def initialize
    @value = ::MissingFieldNamespace::Phantom(Int32).new
  end
end
MissingQualifiedFieldHolder.new
CRYSTAL
cat >"$WORK/arity.cr" <<'CRYSTAL'
module QualifiedArityField
  class Box(T)
  end
end
class WrongArityFieldHolder
  def initialize
    @value = ::QualifiedArityField::Box(Int32, Int64).new
  end
end
WrongArityFieldHolder.new
CRYSTAL
printf 'AAA\n' >"$WORK/expected"
for mode in original lazy eager; do
  mode_env=(env -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == original ]]; then
    args=("$ORIGINAL" 120 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    args=("$COMPILER" 120 8192 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    [[ "$mode" != eager ]] || mode_env+=(ADAMAS_EAGER_MONO=1)
  fi
  for case_name in positive missing arity; do
    log="$WORK/$case_name.$mode.compile.log"
    if CRYSTAL_CACHE_DIR="$WORK/cache.$case_name.$mode" "${mode_env[@]}" "$SAFE_RUNNER" \
        "${args[@]}" "$WORK/$case_name.cr" -o "$WORK/$case_name.$mode.bin" >"$log" 2>&1; then
      [[ "$case_name" == positive ]] || { cat "$log" >&2; echo "FAIL: accepted $case_name [$mode]" >&2; exit 1; }
    else
      status=$?
      if [[ "$case_name" == positive || "$status" != 1 ]]; then
        cat "$log" >&2
        exit 1
      fi
      if [[ "$case_name" == missing ]]; then
        rg -q "undefined (constant|method).*MissingFieldNamespace|undefined method 'new'.*MissingFieldNamespace" "$log"
      else
        rg -q 'wrong number of type vars|expects 1 type args, got 2' "$log"
      fi
      continue
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK/positive.$mode.bin" 5 512 \
        >"$WORK/$mode.stdout" 2>"$WORK/$mode.run.log"; then
      cat "$WORK/$mode.run.log" >&2
      exit 1
    fi
    diff -u "$WORK/expected" "$WORK/$mode.stdout"
  done
  echo "PASS[$mode]: local, qualified and rooted fields; unknown type and arity rejected"
done
