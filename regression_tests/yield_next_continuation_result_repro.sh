#!/usr/bin/env bash
# Compare post-yield execution and the consumed next value against Crystal.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL="${CRYSTAL_BIN:-$(command -v crystal)}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/yield-next-continuation.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/probe.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

class RouteContext
  def initialize(@status : Int32)
  end

  def status : Int32
    @status
  end

  def status=(value : Int32)
    @status = value
  end
end

abstract class Routes
  private def put(context, &callback : RouteContext -> RouteContext)
    callback.call(context)
  end

  private def with_context(context, enabled, *, status = 67, &)
    yield enabled
    context.status = status if enabled
    context
  end

  private def yielding(enabled, *, value, &)
    yield enabled, value
  end
end

class ShovelRoutes < Routes
  def register(context : RouteContext, enabled : Bool)
    put(context) do |request|
      with_context(request, enabled) do |allowed|
        next unless allowed
        LibC.putchar(89)
      end
    end
  end

  def consume(enabled : Bool)
    result = yielding(enabled, value: 90) do |allowed, value|
      next unless allowed
      value
    end
    if result.nil?
      LibC.putchar(78)
    else
      LibC.putchar(result)
    end
  end
end

route = ShovelRoutes.new
LibC.putchar(route.register(RouteContext.new(78), false).status)
LibC.putchar(route.register(RouteContext.new(78), true).status)
route.consume(false)
route.consume(true)
LibC.putchar(10)
LibC.exit(0)
CRYSTAL

sed 's/^      with_context(request, enabled) do/      with_context(request, enabled, status: 67) do/' \
  "$WORK/probe.cr" >"$WORK/named.cr"
sed 's/^      end$/      end\
      41/' "$WORK/probe.cr" >"$WORK/reject.cr"
printf 'NYCNZ\n' >"$WORK/expected"

for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    compile=(env CRYSTAL_CACHE_DIR="$WORK/stock-cache" "$SAFE" "$ORIGINAL" 30 8192 build
      --prelude=empty --single-module --no-debug --link-flags="$LINK_FLAGS")
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    compile=("${mode_env[@]}" "$SAFE" "$CANDIDATE" 30 8192
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  for input in probe named; do
    out="$WORK/$mode-$input"
    "${compile[@]}" "$WORK/$input.cr" -o "$out" >"$out.build.log" 2>&1 || {
      cat "$out.build.log" >&2
      exit 1
    }
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$out" 5 512 >"$out.stdout" 2>"$out.run.log"
    diff -u "$WORK/expected" "$out.stdout"
  done
  out="$WORK/$mode-reject"
  if "${compile[@]}" "$WORK/reject.cr" -o "$out" >"$out.build.log" 2>&1; then
    echo "$mode accepted an Int32 result for the RouteContext callback" >&2
    exit 1
  fi
  rg -q 'expected block.*to return RouteContext, not Int32' "$out.build.log" || {
    cat "$out.build.log" >&2
    exit 1
  }
  printf 'PASS: %s next continuation, consumed result, and typed rejection\n' "$mode"
done
