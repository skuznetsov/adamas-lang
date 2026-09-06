#!/usr/bin/env bash
# An ivar getter must not shadow an explicit overload with the same method name.
# The zero-argument accessor remains available when the overloaded method is
# called without arguments.
set -u -o pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:?usage: $0 COMPILER}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/getter_overload_accessor.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
all_rc=0

run_case() {
  local name="$1"
  local src="$TMP_DIR/$name.cr"
  local out="$TMP_DIR/$name"
  local log="$TMP_DIR/$name.log"
  cat > "$src"
  "$RUN_SAFE" "$COMPILER" 60 4096 "$src" --no-prelude -o "$out" >"$log" 2>&1
  local compile_rc=$?
  local runtime_rc=99
  if [[ $compile_rc -eq 0 && -x "$out" ]]; then
    "$RUN_SAFE" "$out" 5 512 >>"$log" 2>&1
    runtime_rc=$?
  fi
  if [[ $compile_rc -eq 0 && $runtime_rc -eq 0 ]]; then
    echo "PASS[$name] compile=0 runtime=0"
  else
    echo "FAIL[$name] compile=$compile_rc runtime=$runtime_rc"
    cat "$log"
    all_rc=1
  fi
}

run_case collision <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class GetterCollision
  @function_def_overloads : Hash(String, Array(String)) = {} of String => Array(String)
  getter function_def_overloads

  private def function_def_overloads(base : String, stripped : String?) : Array(String)
    ["overload"]
  end

  def probe : Int32
    with_args = function_def_overloads("base", "stripped").size == 1
    no_args = function_def_overloads.size == 0
    with_args && no_args ? 0 : 1
  end
end

LibC.exit(GetterCollision.new.probe)
CR

run_case explicit_zero_arg <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class ExplicitZeroArg
  @value : Int32 = 7

  def value : Int32
    @value
  end

  private def value(prefix : String, suffix : String?) : Int32
    42
  end

  def probe : Int32
    (value == 7 && value("x", "y") == 42) ? 0 : 1
  end
end

LibC.exit(ExplicitZeroArg.new.probe)
CR

run_case synthetic_only <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class SyntheticOnly
  @value : Int32 = 7
  getter value

  def probe : Int32
    value == 7 ? 0 : 1
  end
end

LibC.exit(SyntheticOnly.new.probe)
CR

exit "$all_rc"
