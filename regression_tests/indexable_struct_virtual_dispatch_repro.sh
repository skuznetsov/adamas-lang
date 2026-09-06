#!/bin/bash
set -u

if [ "$#" -lt 1 ]; then
  echo "usage: $0 ADAMAS_COMPILER" >&2
  exit 2
fi

compiler="$1"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_safe="${RUN_SAFE:-$root_dir/scripts/run_safe.sh}"
original_crystal="${ORIGINAL_CRYSTAL:-$(command -v crystal)}"
work_dir="${WORK_DIR:-$(mktemp -d /private/tmp/indexable-struct-dispatch.XXXXXX)}"
keep_work="${KEEP_WORK:-0}"
failures=0

cleanup() {
  if [ "$keep_work" -ne 1 ]; then
    rm -rf "$work_dir"
  else
    echo "artifacts: $work_dir"
  fi
}
trap cleanup EXIT

mkdir -p "$work_dir/cache-adamas" "$work_dir/cache-original"

cat > "$work_dir/basic.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def first(values : Indexable(Int32)) : Int32
  values[0]
end

array = [7, 8]
slice = Slice(Int32).new(2) { |index| index + 9 }

LibC.exit(1) unless first(array) == 7
LibC.exit(2) unless first(slice) == 9
LibC.exit(3) unless array.any? { |value| value == 8 }
LibC.exit(4) unless slice.any? { |value| value == 10 }
LibC.exit(0)
CR

cat > "$work_dir/fetch.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def first(values : Indexable(Int32)) : Int32
  values[0]
end

def fetch_or_default(values : Indexable(Int32), index : Int32) : Int32
  values.fetch(index) { |missing| 100 + missing }
end

array = [7, 8]
slice = Slice(Int32).new(2) { |index| index + 9 }

LibC.exit(1) unless first(array) == 7
LibC.exit(2) unless first(slice) == 9
LibC.exit(3) unless fetch_or_default(array, 1) == 8
LibC.exit(4) unless fetch_or_default(slice, 2) == 102
LibC.exit(5) unless array.any? { |value| value == 8 }
LibC.exit(6) unless slice.any? { |value| value == 10 }
LibC.exit(0)
CR

run_compile() {
  local label="$1"
  local crystal_bin="$2"
  local source="$3"
  local output="$4"
  local cache="$5"
  local log="$work_dir/${label}.compile.log"
  local status

  set +e
  if [[ "$label" == *-original ]]; then
    CRYSTAL_CACHE_DIR="$cache" "$run_safe" "$crystal_bin" 180 8192 build "$source" -o "$output" >"$log" 2>&1
  else
    CRYSTAL_CACHE_DIR="$cache" "$run_safe" "$crystal_bin" 180 8192 "$source" -o "$output" >"$log" 2>&1
  fi
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    echo "FAIL $label compile: exit $status (see $log)"
    failures=$((failures + 1))
  else
    echo "PASS $label compile"
  fi
  return "$status"
}

run_binary() {
  local label="$1"
  local binary="$2"
  local log="$work_dir/${label}.runtime.log"
  local status

  set +e
  "$run_safe" "$binary" 10 512 >"$log" 2>&1
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    echo "FAIL $label runtime: expected exit 0, got $status (see $log)"
    failures=$((failures + 1))
  else
    echo "PASS $label runtime: exit 0"
  fi
  return "$status"
}

for case_name in basic fetch; do
  source="$work_dir/$case_name.cr"
  adamas_bin="$work_dir/$case_name-adamas"
  original_bin="$work_dir/$case_name-original"

  if run_compile "$case_name-adamas" "$compiler" "$source" "$adamas_bin" "$work_dir/cache-adamas"; then
    run_binary "$case_name-adamas" "$adamas_bin" || true
  fi
  if run_compile "$case_name-original" "$original_crystal" "$source" "$original_bin" "$work_dir/cache-original"; then
    run_binary "$case_name-original" "$original_bin" || true
  fi
done

exit "$failures"
