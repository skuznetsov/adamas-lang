#!/usr/bin/env bash
# Regression: typeof(yield ...) is semantic-only.  Lowering it must preserve
# the inlined block return type without executing the callback in the runtime
# control-flow graph.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-crystal}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILE_TIMEOUT="${TYPEOF_YIELD_COMPILE_TIMEOUT:-180}"
COMPILE_MEM="${TYPEOF_YIELD_COMPILE_MEM:-8192}"
RUN_TIMEOUT="${TYPEOF_YIELD_RUN_TIMEOUT:-5}"
RUN_MEM="${TYPEOF_YIELD_RUN_MEM:-512}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi
if ! command -v "$ORIGINAL_CRYSTAL" >/dev/null 2>&1; then
  echo "ERROR: original Crystal compiler not found: $ORIGINAL_CRYSTAL" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typeof_yield_repro.XXXXXX")"
ORIGINAL_CACHE_DIR="$WORK_DIR/original-cache"
mkdir -p "$ORIGINAL_CACHE_DIR"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/empty_any.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct ProbeRange
  def initialize(@begin : Int32, @end : Int32)
  end

  def each(&) : Nil
    current = @begin
    typeof(yield current)
    while current < @end
      yield current
      current = current + 1
    end
  end

  def any?(& : Int32 -> Bool) : Bool
    each { |element| return true if yield element }
    false
  end
end

calls = 0
result = ProbeRange.new(0, 0).any? { calls += 1; true }
LibC.exit(result ? 100 + calls : calls)
CRYSTAL

cat >"$WORK_DIR/nonempty_any.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct ProbeRange
  def initialize(@begin : Int32, @end : Int32)
  end

  def each(&) : Nil
    current = @begin
    typeof(yield current)
    while current < @end
      yield current
      current = current + 1
    end
  end

  def any?(& : Int32 -> Bool) : Bool
    each { |element| return true if yield element }
    false
  end
end

calls = 0
result = ProbeRange.new(0, 3).any? { calls += 1; false }
LibC.exit(result ? 100 + calls : calls)
CRYSTAL

cat >"$WORK_DIR/nested_any.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

struct ProbeRange
  def initialize(@begin : Int32, @end : Int32)
  end

  def each(&) : Nil
    current = @begin
    typeof(yield current)
    while current < @end
      yield current
      current = current + 1
    end
  end

  def any?(& : Int32 -> Bool) : Bool
    each { |element| return true if yield element }
    false
  end
end

calls = 0
result = ProbeRange.new(0, 2).any? do |_element|
  ProbeRange.new(0, 0).any? { calls += 1; true }
  false
end
LibC.exit(result ? 100 + calls : calls)
CRYSTAL

cat >"$WORK_DIR/type_identity.cr" <<'CRYSTAL'
struct ProbeRange
  def initialize(@begin : Int32, @end : Int32)
  end

  def each(&) : Nil
    current = @begin
    local_value = current
    if current < @end
      local_value = current + 1
    end
    puts typeof(yield local_value)
    while current < @end
      yield current
      current = current + 1
    end
  end
end

ProbeRange.new(0, 0).each { |value| value + 1 }
ProbeRange.new(0, 0).each { |_value| "typed" }
CRYSTAL

cat >"$WORK_DIR/array_uniq_stock.cr" <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

values = ["a", "a", "b"]
values.uniq!
LibC.exit(values.size)
CRYSTAL

cat >"$WORK_DIR/handler_stock.cr" <<'CRYSTAL'
macro record(name, *properties)
  struct {{name.id}}
    {% for property in properties %}
      {% if property.is_a?(TypeDeclaration) %}
        getter {{property.var.id}} : {{property.type}}
      {% end %}
    {% end %}

    def initialize({{
      properties.map do |field|
        "@#{field.id}".id
      end.splat
    }})
    end
  end
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

class Owner
  record Handler, value : Int32
end

recorded = Owner::Handler.new(73)
LibC.exit(recorded.value == 73 ? 0 : 1)
CRYSTAL

extract_stdout() {
  local log="$1"
  local output="$2"
  awk '
    /^=== STDOUT ===$/ { in_stdout = 1; next }
    /^=== STDERR ===$/ { in_stdout = 0 }
    in_stdout { print }
  ' "$log" >"$output"
}

run_case() {
  local name="$1"
  local mode="$2"
  local expected_rc="$3"
  local expected_stdout="$4"
  local source="$WORK_DIR/$name.cr"
  local original_bin="$WORK_DIR/$name.original.bin"
  local stage_bin="$WORK_DIR/$name.stage.bin"
  local original_compile_log="$WORK_DIR/$name.original.compile.log"
  local stage_compile_log="$WORK_DIR/$name.stage.compile.log"
  local original_run_log="$WORK_DIR/$name.original.run.log"
  local stage_run_log="$WORK_DIR/$name.stage.run.log"
  local original_stdout="$WORK_DIR/$name.original.stdout"
  local stage_stdout="$WORK_DIR/$name.stage.stdout"
  local expected_file="$WORK_DIR/$name.expected.stdout"
  local -a original_flags=()
  local -a stage_flags=()

  if [[ "$mode" == "noprelude" ]]; then
    # The upstream control uses its normal prelude; this keeps arithmetic and
    # process-exit primitives available.  The Adamas side is the no-prelude
    # oracle under test.
    stage_flags+=(--no-prelude)
  fi

  set +e
  env CRYSTAL_CACHE_DIR="$ORIGINAL_CACHE_DIR" \
    "$RUN_SAFE" "$ORIGINAL_CRYSTAL" "$COMPILE_TIMEOUT" "$COMPILE_MEM" \
    build "$source" "${original_flags[@]}" -o "$original_bin" \
    >"$original_compile_log" 2>&1
  local original_compile_rc=$?
  "$RUN_SAFE" "$COMPILER" "$COMPILE_TIMEOUT" "$COMPILE_MEM" \
    "$source" "${stage_flags[@]}" -o "$stage_bin" \
    >"$stage_compile_log" 2>&1
  local stage_compile_rc=$?
  set -e

  if [[ $original_compile_rc -ne 0 || $stage_compile_rc -ne 0 ]]; then
    echo "FAIL[$name]: compile original=$original_compile_rc stage=$stage_compile_rc" >&2
    [[ $original_compile_rc -eq 0 ]] || tail -40 "$original_compile_log" >&2
    [[ $stage_compile_rc -eq 0 ]] || tail -40 "$stage_compile_log" >&2
    return 1
  fi

  set +e
  "$RUN_SAFE" "$original_bin" "$RUN_TIMEOUT" "$RUN_MEM" \
    >"$original_run_log" 2>&1
  local original_run_rc=$?
  "$RUN_SAFE" "$stage_bin" "$RUN_TIMEOUT" "$RUN_MEM" \
    >"$stage_run_log" 2>&1
  local stage_run_rc=$?
  set -e

  extract_stdout "$original_run_log" "$original_stdout"
  extract_stdout "$stage_run_log" "$stage_stdout"
  printf '%s' "$expected_stdout" >"$expected_file"

  if [[ $original_run_rc -ne $expected_rc || $stage_run_rc -ne $expected_rc ]]; then
    echo "FAIL[$name]: runtime original=$original_run_rc stage=$stage_run_rc expected=$expected_rc" >&2
    tail -30 "$original_run_log" >&2 || true
    tail -30 "$stage_run_log" >&2 || true
    return 1
  fi
  if ! diff -u "$expected_file" "$original_stdout" >/dev/null 2>&1 ||
     ! diff -u "$expected_file" "$stage_stdout" >/dev/null 2>&1; then
    echo "FAIL[$name]: stdout differs from expected" >&2
    diff -u "$expected_file" "$original_stdout" >&2 || true
    diff -u "$expected_file" "$stage_stdout" >&2 || true
    return 1
  fi

  echo "PASS[$name]: rc=$expected_rc stdout=$(printf '%q' "$expected_stdout")"
}

failures=0
run_case empty_any noprelude 0 "" || failures=$((failures + 1))
run_case nonempty_any noprelude 3 "" || failures=$((failures + 1))
run_case nested_any noprelude 0 "" || failures=$((failures + 1))
run_case type_identity prelude 0 $'Int32\nString\n' || failures=$((failures + 1))

if [[ "${TYPEOF_YIELD_STDLIB_CONTROLS:-0}" == "1" ]]; then
  run_case array_uniq_stock prelude 2 "" || failures=$((failures + 1))
  run_case handler_stock prelude 0 "" || failures=$((failures + 1))
else
  echo "SKIP[stdlib_controls]: set TYPEOF_YIELD_STDLIB_CONTROLS=1 to run known wider-frontier controls"
fi

if [[ $failures -ne 0 ]]; then
  echo "FAIL: typeof(yield ...) core regression cases failed: $failures" >&2
  exit 1
fi
echo "PASS: typeof(yield ...) core is compile-time-only and preserves inline block return types"
