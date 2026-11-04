#!/usr/bin/env bash
# A next owned by an inner block or loop must not materialize its outer block.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nested-next-owner.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

cat > "$WORK/probe.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
end

class Host
  def marker : Int32
    72
  end
end

class Store
  @host : Host

  def initialize
    @host = Host.new
  end

  def []?(key : Int32) : Host?
    key == 1 ? @host : nil
  end
end

class Params
  def []?(key : Int32) : Int32?
    key == 1 ? 1 : nil
  end
end

class Controller
  @hosts : Store

  def initialize
    @hosts = Store.new
  end

  def with_host(params, *, key = 1, &)
    if (name = params[key]?) && (host = @hosts[name]?)
      yield host
    end
  end

  def consume(host : Host) : Int32
    LibC.putchar(host.marker)
  end

  def visit(flag : Bool, &)
    yield flag
  end

  def skip_iteration(flag : Bool) : Bool
    flag
  end

  def run(flag : Bool)
    params = Params.new
    with_host(params) { |host| consume(host) }
    with_host(params) do |host|
      value = visit(flag) do |skip|
        next 78 if skip
        73
      end
      LibC.putchar(value)
      running = true
      while running
        running = false
        next if skip_iteration(flag)
        LibC.putchar(76)
      end
      consume(host)
    end
  end
end

controller = Controller.new
controller.run(LibC.getpid < 0)
controller.run(LibC.getpid > 0)
CRYSTAL

for mode in stock lazy eager; do
  output="$WORK/$mode"
  if [[ "$mode" == stock ]]; then
    compile=(env CRYSTAL_CACHE_DIR="$WORK/cache.stock" "$SAFE" "$ORIGINAL" 20 512 build
      --prelude=empty --single-module --no-debug --link-flags="$LINK_FLAGS")
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    compile=("${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$CANDIDATE" 20 512
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  "${compile[@]}" "$WORK/probe.cr" -o "$output" > "$output.compile.log" 2>&1 || {
    cat "$output.compile.log" >&2
    exit 1
  }
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 \
    > "$output.stdout" 2> "$output.run.log" || {
    cat "$output.run.log" >&2
    exit 1
  }
  printf '%s' HILHHNH > "$WORK/expected"
  diff -u "$WORK/expected" "$output.stdout"
  printf 'PASS: %s nested next owners\n' "$mode"
done
