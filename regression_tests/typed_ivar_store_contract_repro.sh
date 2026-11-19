#!/usr/bin/env bash
# Check source assignment restrictions for explicitly typed instance variables.
# Cover compatible stores, typed readback, and a terminating RHS.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal || true)}}"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
DEFAULT_LINK_FLAGS=""
if [[ "$(uname -s)" == "Darwin" ]]; then
  DEFAULT_LINK_FLAGS="-L/opt/homebrew/lib -lgc -fuse-ld=/usr/bin/ld"
fi
STOCK_LINK_FLAGS="${ORIGINAL_CRYSTAL_LINK_FLAGS:-$DEFAULT_LINK_FLAGS}"
ADAMAS_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:-$DEFAULT_LINK_FLAGS}"

if [[ -z "$CRYSTAL_BIN" || ! -x "$CRYSTAL_BIN" ]]; then
  echo "set CRYSTAL_BIN or install crystal on PATH" >&2
  exit 2
fi
if [[ ! -x "$ADAMAS_BIN" ]]; then
  echo "Adamas compiler is not executable: $ADAMAS_BIN" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typed-ivar-store.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

export RUN_SAFE_PASSTHROUGH_STDIO=1

cat > "$WORK_DIR/invalid-orassign.cr" <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

class Job
end

class Scheduler
  @job : Job?

  def fetch
    @job ||= 65
  end
end

Scheduler.new.fetch
LibC.putchar(65)
CR

cat > "$WORK_DIR/invalid-explicit-or.cr" <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

class Job
end

class Scheduler
  @job : Job?

  def fetch
    @job = @job || 65
  end
end

Scheduler.new.fetch
LibC.putchar(65)
CR

cat > "$WORK_DIR/valid.cr" <<'CR'
lib LibC
  fun putchar(c : Int32) : Int32
end

class Base
end

class Child < Base
end

enum Status
  Ready
end

class Scheduler
  @job : Base?
  @count : Int32?
  @wide : Int64?
  @ratio : Float64?
  @number : Int64 | Float64 | Nil
  @payload : Int32 | String | Nil
  @fallback : Int64?
  @explicit_fallback : Int32?
  @status : Status?
  @small : UInt8?
  @pair : Tuple(Int32, Int32)

  def initialize
    @job ||= Child.new
    @count ||= 65
    @wide = 42
    @ratio = 3
    @number = 42_i64
    set_payload(42)
    set_payload("ok")
    @fallback ||= 44
    @explicit_fallback = @explicit_fallback || 45
    @status = Status::Ready
    @small = 255
    @pair = {7, 9}
  end

  def verify
    LibC.putchar((@count || -1_i32) == 65_i32 ? 67 : 88)
    LibC.putchar(@number.is_a?(Int64) ? 85 : 88)
    LibC.putchar(@payload.is_a?(String) ? 80 : 88)
    LibC.putchar((@explicit_fallback || -1_i32) == 45_i32 ? 69 : 88)
    LibC.putchar(@status.is_a?(Status) ? 83 : 88)
    LibC.putchar(@pair[0] == 7_i32 && @pair[1] == 9_i32 ? 84 : 88)
    @job = nil
    @count = nil
    LibC.putchar(@job.is_a?(Nil) && @count.is_a?(Nil) ? 78 : 88)
    LibC.putchar(10)
  end

  def set_payload(value : Int32 | String)
    @payload = value
  end
end

Scheduler.new.verify
CR

cat > "$WORK_DIR/numeric-dynamic-invalid.cr" <<'CR'
class NumericField
  @wide : Int64?

  def set(value : Int32)
    @wide = value
  end
end

NumericField.new.set(42)
CR

cat > "$WORK_DIR/numeric-out-of-range-invalid.cr" <<'CR'
class NumericField
  @small : UInt8?

  def initialize
    @small = 300
  end
end

NumericField.new
CR

cat > "$WORK_DIR/numeric-explicit-or-invalid.cr" <<'CR'
class NumericField
  @wide : Int64?

  def set
    @wide = @wide || 42
  end
end

NumericField.new.set
CR

cat > "$WORK_DIR/union-member-invalid.cr" <<'CR'
class UnionField
  @payload : Int32 | String | Nil

  def set(value : Int32 | Bool)
    @payload = value
  end
end

UnionField.new.set(true)
CR

cat > "$WORK_DIR/non-numeric-user-type-invalid.cr" <<'CR'
struct NumericName
  def to_i64 : Int64
    42_i64
  end
end

class NumericField
  @wide : Int64?

  def set(value : NumericName)
    @wide = value
  end
end

NumericField.new.set(NumericName.new)
CR

cat > "$WORK_DIR/tuple-invalid.cr" <<'CR'
class TupleField
  @pair : Tuple(Int32, Int32)

  def initialize
    @pair = {0, 0}
  end

  def set(value : Tuple(Int32, Bool))
    @pair = value
  end
end

TupleField.new.set({7, true})
CR

cat > "$WORK_DIR/never-stores.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class NeverStores
  @item : Int32

  def initialize
    @item = 5
  end

  def stop : Nil
    @item = LibC.exit(27)
  end
end

NeverStores.new.stop
CR


compile() {
  local stage="$1" compiler="$2" fixture="$3" out="$4"
  if [[ "$stage" == stock ]]; then
    local -a args=(build --prelude=empty)
    [[ -z "$STOCK_LINK_FLAGS" ]] || args+=("--link-flags=$STOCK_LINK_FLAGS")
    "$SAFE_RUNNER" "$compiler" 90 8192 "${args[@]}" "$WORK_DIR/$fixture.cr" -o "$out"
  else
    ADAMAS_EXTRA_LINK_FLAGS="$ADAMAS_LINK_FLAGS" \
      "$SAFE_RUNNER" "$compiler" 90 8192 "$WORK_DIR/$fixture.cr" \
      --no-prelude --no-ast-cache --no-llvm-cache -o "$out"
  fi
}

check_rejection() {
  local stage="$1" compiler="$2" fixture="$3" field="$4" rejected_type="$5"
  local out="$WORK_DIR/$stage-$fixture" status=0
  compile "$stage" "$compiler" "$fixture" "$out" >"$out.log" 2>&1 || status=$?
  if [[ "$status" != 1 || -e "$out" ]] ||
      ! grep -F "instance variable '$field'" "$out.log" |
        grep -Eq "must be .* not $rejected_type"; then
    cat "$out.log" >&2
    echo "FAIL $stage/$fixture: expected rejection of incompatible store to $field" >&2
    return 1
  fi
  echo "PASS $stage/$fixture: rejected incompatible store"
}

check_valid() {
  local stage="$1" compiler="$2" fixture="$3" expected_exit="$4" expected_output="$5"
  local out="$WORK_DIR/$stage-$fixture" status=0
  if ! compile "$stage" "$compiler" "$fixture" "$out" >"$out.log" 2>&1 || [[ ! -x "$out" ]]; then
    cat "$out.log" >&2
    echo "FAIL $stage/$fixture: expected compatible source to compile" >&2
    return 1
  fi
  "$SAFE_RUNNER" "$out" 10 512 >"$out.stdout" 2>"$out.stderr" || status=$?
  if [[ "$status" != "$expected_exit" ]] || ! printf '%s' "$expected_output" | cmp -s - "$out.stdout"; then
    cat "$out.stdout" "$out.stderr" >&2
    echo "FAIL $stage/$fixture: expected exit $expected_exit and matching output" >&2
    return 1
  fi
  echo "PASS $stage/$fixture: compatible source and execution"
}

check_stage() {
  local stage="$1" compiler="$2"
  check_rejection "$stage" "$compiler" invalid-orassign @job 'Int32$'
  check_rejection "$stage" "$compiler" invalid-explicit-or @job '(Int32|\(Int32 \| Job\))$'
  check_rejection "$stage" "$compiler" numeric-dynamic-invalid @wide 'Int32$'
  check_rejection "$stage" "$compiler" numeric-out-of-range-invalid @small 'Int32$'
  check_rejection "$stage" "$compiler" numeric-explicit-or-invalid @wide '(Int32|\(Int32 \| Int64\))$'
  check_rejection "$stage" "$compiler" union-member-invalid @payload '(Bool|\(Bool \| Int32\)|\(Int32 \| Bool\))$'
  check_rejection "$stage" "$compiler" non-numeric-user-type-invalid @wide 'NumericName$'
  check_rejection "$stage" "$compiler" tuple-invalid @pair 'Tuple\(Int32, Bool\)$'
  check_valid "$stage" "$compiler" valid 0 $'CUPESTN\n'
  check_valid "$stage" "$compiler" never-stores 27 ''
}

check_stage stock "$CRYSTAL_BIN"
check_stage adamas "$ADAMAS_BIN"
echo "PASS: explicit ivar assignment restrictions agree with stock Crystal"
