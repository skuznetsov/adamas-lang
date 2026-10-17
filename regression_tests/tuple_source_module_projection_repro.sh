#!/usr/bin/env bash
# Builtin Tuple source includes retain their arena and variadic element union
# before lazy module methods register. Invalid projections must still reject.
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
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tuple-source-module-projection.XXXXXX")"
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
lib TupleProjectionC
  fun putchar(value : Int32) : Int32
end

def accept_strings(value : Enumerable(String))
  65
end

def accept_indexable(value : Indexable(String))
  66
end

def accept_union(value : Enumerable(String | Int32))
  67
end

def accept_nested(value : Enumerable(Array(String)))
  68
end

TupleProjectionC.putchar(accept_strings({"a", "b", "c", "d"}))
TupleProjectionC.putchar(accept_strings({"single"}))
TupleProjectionC.putchar(accept_indexable({"a", "b"}))
TupleProjectionC.putchar(accept_union({"a", 1}))
TupleProjectionC.putchar(accept_nested({["a"] of String, ["b"] of String}))

def accepts_union(value : Enumerable(String | Int32))
  65
end
def accepts_nil(value : Enumerable(Int32 | Nil))
  66
end
def accepts_nested(value : Indexable(Array(String | Int32)))
  67
end
TupleProjectionC.putchar(accepts_union({1, "a", 1}))
TupleProjectionC.putchar(accepts_nil({nil, 1, nil}))
TupleProjectionC.putchar(accepts_nested({["a", 1] of String | Int32}))

alias TupleProjectionPair = ::Tuple(String, String)
def through_rooted(value : ::Tuple(String, String))
  accept_strings(value)
end
def through_alias(value : TupleProjectionPair)
  accept_strings(value)
end
TupleProjectionC.putchar(through_rooted({"a", "b"}))
TupleProjectionC.putchar(through_alias({"a", "b"}))
TupleProjectionC.putchar(10)
CRYSTAL
cat >"$WORK/wrong_element.cr" <<'CRYSTAL'
def reject_projection(value : Enumerable(String))
  7
end
reject_projection({"a", true})
CRYSTAL
cat >"$WORK/wrong_nested.cr" <<'CRYSTAL'
def reject_projection(value : Enumerable(Array(String)))
  7
end
reject_projection({[1] of Int32, [2] of Int32})
CRYSTAL
cat >"$WORK/wrong_namespace.cr" <<'CRYSTAL'
module ProjectionShadow::Enumerable(T)
end
def reject_projection(value : ProjectionShadow::Enumerable(String))
  7
end
reject_projection({"a", "b"})
CRYSTAL
printf 'AABCDABCAA\n' >"$WORK/control.expected"
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
  if [[ "$name" != control ]]; then
    compile "$stage" "$name" || status=$?
    if [[ "$status" != 1 || -e "$WORK/$stage.$name.bin" ]]; then
      cat "$WORK/$stage.$name.compile.log" >&2
      printf 'FAIL %s: Incompatible projection requires rc1/no executable, got %s\n' "$stage" "$status" >&2
      return 1
    fi
    rg -q '(Bool|Int32|ProjectionShadow)' "$WORK/$stage.$name.compile.log"
    rg -q '(Enumerable|String)'  "$WORK/$stage.$name.compile.log"
  else
    if ! compile "$stage" "$name"; then cat "$WORK/$stage.$name.compile.log" >&2; return 1; fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 10 512 "$WORK/$stage.$name.bin" "$WORK/$stage.$name.stderr" >"$WORK/$stage.$name.stdout" 2>"$WORK/$stage.$name.run.log"
    test ! -s "$WORK/$stage.$name.stderr"
    cmp "$WORK/$name.expected" "$WORK/$stage.$name.stdout"
  fi
}
for name in control wrong_element wrong_nested wrong_namespace; do check original "$name"; done
for name in control wrong_element wrong_nested wrong_namespace; do check candidate "$name"; done
printf 'PASS: Tuple source projections preserve variadic include arguments\n'
