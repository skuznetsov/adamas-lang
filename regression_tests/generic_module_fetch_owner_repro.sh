#!/usr/bin/env bash
# Generic module methods must call block overloads with the concrete receiver.
# Array(Wide) and Array(Bool) intentionally have different element layouts.
set -u -o pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:?usage: $0 COMPILER}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-module-fetch.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
failed=0

run_case() {
  local name="$1" declaration="$2" call_receiver="$3" reverse="$4"
  local source="$WORK_DIR/$name.cr" output="$WORK_DIR/$name" log="$WORK_DIR/$name.log"
  cat >"$source" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end
$declaration
  def fetch(index : Int32, &)
    return yield index if index < 0 || index >= size
    unsafe_fetch(index)
  end
  def fetch(index, default)
    ${call_receiver}fetch(index) { default }
  end
end
CR
  if [[ "$declaration" == 'module SharedFetch(T)' ]]; then
    cat >>"$source" <<'CR'
class Array(T)
  include SharedFetch(T)
end
CR
  fi
  cat >>"$source" <<'CR'
# Every fixture array has one element. Supply a real size body because the
# no-prelude runtime does not provide the stdlib Array#size implementation.
class Array(T)
  def size : Int32
    1
  end
end
struct Wide
  def initialize(@a : Int64, @b : Int64, @c : Int64)
  end
end
def wide_probe(values : Array(Wide))
  values.fetch(0, nil)
end
def bool_probe(values : Array(Bool))
  values.fetch(0, nil)
end
def missing_probe(values : Array(Bool))
  values.fetch(1, nil)
end
CR
  if [[ "$reverse" == 1 ]]; then
    echo 'result = bool_probe([true])' >>"$source"
    echo 'wide_probe([Wide.new(1_i64, 2_i64, 3_i64)])' >>"$source"
  else
    echo 'wide_probe([Wide.new(1_i64, 2_i64, 3_i64)])' >>"$source"
    echo 'result = bool_probe([true])' >>"$source"
  fi
  cat >>"$source" <<'CR'
LibC.exit(21) unless result
LibC.exit(22) if bool_probe([false])
LibC.exit(23) if missing_probe([true])
LibC.exit(0)
CR
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 "$source" --no-prelude -o "$output" >"$log" 2>&1
  local compile_rc=$? runtime_rc=99
  if [[ "$compile_rc" == 0 && -x "$output" ]]; then
    "$ROOT_DIR/scripts/run_safe.sh" "$output" 5 512 >>"$log" 2>&1
    runtime_rc=$?
  fi
  if [[ "$compile_rc" == 0 && "$runtime_rc" == 0 ]]; then
    echo "PASS[$name]"
  else
    echo "FAIL[$name] compile=$compile_rc runtime=$runtime_rc"
    cat "$log"
    failed=1
  fi
}
run_case module 'module SharedFetch(T)' '' 0
run_case module_explicit_self 'module SharedFetch(T)' 'self.' 0
run_case module_reverse 'module SharedFetch(T)' '' 1
run_case direct_array 'class Array(T)' '' 0
exit "$failed"
