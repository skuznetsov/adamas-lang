#!/usr/bin/env bash
# A terminating inherited implementation may narrow the guard's continuation.
# A returning override, including through nested modules, must keep it nilable.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
candidate="${1:?usage: $0 /path/to/adamas}"
original="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/adamas-inherited-virtual-noreturn.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache"

stock_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  stock_link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

write_probe() {
  local mode="$1"
  cat <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class GuardBase
  private def stop
    LibC.exit(23)
  end

  private def fail_guard
    stop()
  end
end
CR
  if [[ "$mode" == include ]]; then
    cat <<'CR'
module ReturningStop
  private def stop
    nil
  end
end

module NestedStop
  include ReturningStop
end
CR
  fi
  echo 'class Guard < GuardBase'
  case "$mode" in
    include)
      echo '  include NestedStop'
      ;;
    override)
      cat <<'CR'
  private def stop
    nil
  end
CR
      ;;
  esac
  cat <<'CR'
  private def consume(value : Int32)
    value
  end

  private def with_value(flag : Bool, &)
    value = flag ? 7 : nil
    fail_guard() unless value
    yield consume(value)
  end

  def run(flag : Bool)
    with_value(flag) { |value| value }
  end
end

guard = Guard.new
LibC.exit(1) unless guard.run(true) == 7
guard.run(false)
LibC.exit(2)
CR
}

check() {
  local compiler="$1" mode="$2" status=0
  local source="$work/$mode.cr" output="$work/$compiler.$mode"
  local command=()
  if [[ "$compiler" == crystal ]]; then
    command=("$original" 60 4096 build --prelude=empty --no-color "${stock_link[@]}")
  else
    command=("$candidate" 60 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi

  "$safe" "${command[@]}" --no-debug "$source" -o "$output" >"$output.compile.log" 2>&1 || status=$?
  if [[ "$mode" == inherited ]]; then
    if [[ "$status" != 0 ]]; then
      cat "$output.compile.log" >&2
      return 1
    fi
    "$safe" "$output" 5 512 >"$output.run.log" 2>&1 || status=$?
    if [[ "$status" != 23 ]] || ! grep -Fq '[EXIT: 23]' "$output.run.log"; then
      cat "$output.run.log" >&2
      return 1
    fi
  else
    if [[ "$status" != 1 ]] || ! grep -Eq '^[Ee]rror: .*Guard#consume.*(Nil.*Int32|Int32.*Nil)' "$output.compile.log"; then
      cat "$output.compile.log" >&2
      return 1
    fi
  fi
  printf 'PASS[%s] %s\n' "$compiler" "$mode"
}

for mode in inherited override include; do
  write_probe "$mode" >"$work/$mode.cr"
  check crystal "$mode"
  check adamas "$mode"
done
