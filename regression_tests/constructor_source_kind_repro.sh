#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:-$root/bin/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-constructor-source-kind.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "${KEEP_ARTIFACTS:-0}" == "1" || "$status" -ne 0 ]]; then
    printf 'ARTIFACTS retained: %s\n' "$work" >&2
  else
    rm -rf -- "$work"
  fi
}
trap cleanup EXIT
cd "$work"
export TMPDIR="$work" CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO
if [[ -n "${TRACE_CONSTRUCTOR_ALLOCATORS:-}" ]]; then
  export ADAMAS_TRACE_ALLOCATOR_OVERLOAD="$TRACE_CONSTRUCTOR_ALLOCATORS"
fi
original_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_flags=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi

cat > positive.cr <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

class Payload
end

class DirectRoute
  @marker : Int32

  def initialize(value : Payload)
    @marker = 65
  end

  def initialize(value : Payload.class)
    @marker = 66
  end

  def marker : Int32
    @marker
  end
end

class UnionRoute
  @marker : Int32

  def initialize(value : Payload | Int32)
    @marker = 67
  end

  def initialize(value : Payload.class | Int32)
    @marker = 68
  end

  def marker : Int32
    @marker
  end
end

class UnionRouteReverse
  @marker : Int32

  def initialize(value : Payload.class | Int32)
    @marker = 76
  end

  def initialize(value : Payload | Int32)
    @marker = 75
  end

  def marker : Int32
    @marker
  end
end

class MethodRoute
  def route(value : Payload | Int32) : Int32
    71
  end

  def route(value : Payload.class | Int32) : Int32
    72
  end
end

class MethodRouteReverse
  def route(value : Payload.class | Int32) : Int32
    74
  end

  def route(value : Payload | Int32) : Int32
    73
  end
end

class ScalarRoute
  @marker : Int32

  def initialize(value : Payload | Int32)
    @marker = 69
  end

  def marker : Int32
    @marker
  end
end

class MixedRoute
  @marker : Int32

  def initialize(value : Payload | Payload.class)
    @marker = 70
  end

  def marker : Int32
    @marker
  end
end

def mixed_route(flag : Bool) : Int32
  MixedRoute.new(if flag
    Payload.new
  else
    Payload
  end).marker
end

LibC.putchar(DirectRoute.new(Payload.new).marker)
LibC.putchar(DirectRoute.new(Payload).marker)
LibC.putchar(UnionRoute.new(Payload.new).marker)
LibC.putchar(UnionRoute.new(Payload).marker)
LibC.putchar(ScalarRoute.new(42).marker)
LibC.putchar(mixed_route(true))
LibC.putchar(mixed_route(false))
LibC.putchar(UnionRouteReverse.new(Payload.new).marker)
LibC.putchar(UnionRouteReverse.new(Payload).marker)
route = MethodRoute.new
LibC.putchar(route.route(Payload.new))
LibC.putchar(route.route(Payload))
route_reverse = MethodRouteReverse.new
LibC.putchar(route_reverse.route(Payload.new))
LibC.putchar(route_reverse.route(Payload))
CR

cat > reject_class_object.cr <<'CR'
class Payload
end

class RejectClassObject
  def initialize(value : Payload | Int32)
  end
end

RejectClassObject.new(Payload)
CR

cat > reject_mixed_value_facts.cr <<'CR'
class Payload
end

class RejectMixedKinds
  def initialize(value : Payload | Int32)
  end
end

def reject_mixed(flag : Bool)
  RejectMixedKinds.new(if flag
    Payload.new
  else
    Payload
  end)
end

reject_mixed(true)
CR

build_original() {
  "$safe" "$original" 60 4096 build "$1.cr" --prelude=empty --single-module \
    --no-debug "${original_flags[@]}" -o "$1.original"
}

build_candidate() {
  "$safe" "$candidate" 60 4096 "$1.cr" --no-prelude --no-debug \
    --no-ast-cache --no-llvm-cache -o "$1.candidate"
}

expect_rejection() {
  local compiler="$1" mode="$2" source="$3" output="$4"
  local status=0
  local -a command
  if [[ "$mode" == original ]]; then
    command=("$safe" "$compiler" 60 4096 build "$source.cr" --prelude=empty --single-module --no-debug "${original_flags[@]}" -o "$output")
  else
    command=("$safe" "$compiler" 60 4096 "$source.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output")
  fi
  "${command[@]}" > "$output.log" 2>&1 || status=$?
  if [[ "$status" -ne 1 ]]; then
    echo "FAIL[$mode/$source]: expected semantic rejection with exit 1, got $status" >&2
    cat "$output.log" >&2
    exit 1
  fi
  if ! grep -Eiq 'Error: expected argument|error: no overload matches' "$output.log"; then
    echo "FAIL[$mode/$source]: nonzero exit lacked an overload/type diagnostic" >&2
    cat "$output.log" >&2
    exit 1
  fi
  if [[ -e "$output" ]]; then
    echo "FAIL[$mode/$source]: rejected compile left an executable" >&2
    exit 1
  fi
}

build_original positive > positive.original.log 2>&1 || { cat positive.original.log >&2; exit 1; }
build_candidate positive > positive.candidate.log 2>&1 || { cat positive.candidate.log >&2; exit 1; }
"$safe" "$work/positive.original" 5 512 > positive.original.out
"$safe" "$work/positive.candidate" 5 512 > positive.candidate.out
printf ABCDEFFKLGHIJ | diff -u - positive.original.out
diff -u positive.original.out positive.candidate.out

expect_rejection "$original" original reject_class_object reject_class_object.original
expect_rejection "$candidate" candidate reject_class_object reject_class_object.candidate
expect_rejection "$original" original reject_mixed_value_facts reject_mixed_value_facts.original
expect_rejection "$candidate" candidate reject_mixed_value_facts reject_mixed_value_facts.candidate

printf 'PASS constructor source-kind overloads and mixed-value facts\n'
