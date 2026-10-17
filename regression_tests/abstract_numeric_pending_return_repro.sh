#!/usr/bin/env bash
# Pending abstract numeric returns must not pin a caller to a placeholder ABI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
CANDIDATE="${1:-$ROOT/bin/adamas}"
[[ -x "$SAFE" && -x "$ORIGINAL" && -x "$CANDIDATE" ]] || exit 2
WORK="$(mktemp -d "${TMPDIR:-/tmp}/abstract-numeric-tag-value.XXXXXX")"
cleanup() {
  local rc=$?
  rm -rf "$WORK/original.cache" "$WORK/candidate.cache"
  if [[ "$rc" == 0 ]]; then
    rm -rf "$WORK"
  else
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  fi
}
trap cleanup EXIT

cat >"$WORK/run_program" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
binary="$1"
program_stderr="$2"
shift 2
exec "$binary" "$@" 2>"$program_stderr"
RUNNER
chmod +x "$WORK/run_program"

cat >"$WORK/abstract_numeric_tag_value.cr" <<'NUMERIC_RETURN_FIXTURE'
require "c/stdio"

lib LibC
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
  fun exit(status : Int32) : NoReturn
end

def report_numeric(value : Int32)
  LibC.putchar(73) # I: accidental narrow signed integer result
  LibC.putchar(59)
end

def report_numeric(value : Int64)
  LibC.putchar(76) # L: signed 64-bit result
  LibC.putchar(value == 4_294_967_297_i64 ? 49 : 48)
  LibC.putchar(59)
end

def report_numeric(value : UInt64)
  LibC.putchar(85) # U: unsigned 64-bit result
  LibC.putchar(value == 4_294_967_297_u64 ? 49 : 48)
  LibC.putchar(59)
end

def report_numeric(value : Float32)
  LibC.putchar(70) # F: 32-bit float result
  LibC.putchar(value == 1.25_f32 ? 49 : 48)
  LibC.putchar(59)
end

def report_numeric(value : Float64)
  LibC.putchar(68) # D: accidental widened float result
  LibC.putchar(value == 1.25_f64 ? 49 : 48)
  LibC.putchar(59)
end

def tag_int_return : Int
  4_294_967_297_u64
end

def forward_int_return
  tag_int_return
end

def tag_float_return : Float
  1.25_f32
end

def forward_float_return
  tag_float_return
end

def tag_number_uint_return : Number
  4_294_967_297_u64
end

def forward_number_uint_return
  tag_number_uint_return
end

def tag_number_float_return : Number
  1.25_f32
end

def forward_number_float_return
  tag_number_float_return
end

module NumericReturnOrderA
  def self.pick : Int
    4_294_967_297_u64
  end

  def self.pick(flag : Bool) : Float
    1.25_f32
  end

  def self.pick(flag : Bool, second : Bool) : Number
    1.25_f32
  end

  def self.int_call
    self.pick
  end

  def self.float_call
    self.pick(true)
  end

  def self.number_float_call
    self.pick(true, true)
  end
end

module NumericReturnOrderB
  def self.pick(flag : Bool, second : Bool) : Number
    1.25_f32
  end

  def self.pick(flag : Bool) : Float
    1.25_f32
  end

  def self.pick : Int
    4_294_967_297_u64
  end

  def self.int_call
    self.pick
  end

  def self.float_call
    self.pick(true)
  end

  def self.number_float_call
    self.pick(true, true)
  end
end

def pending_bottom_int : Int
  LibC.exit(0)
end

def pending_bottom_or_uint64
  if LibC.getpid() < 0
    pending_bottom_int
  else
    4_294_967_297_u64
  end
end

def pending_redefined_int : Int
  17_i32
end

def forward_pending_redefined_int
  pending_redefined_int
end

def pending_redefined_int : Int
  4_294_967_297_u64
end

# A single restricted consumer checks the static result as well as its payload.
def only_pending_uint64(value : UInt64)
  LibC.putchar(85)
  LibC.putchar(value == 4_294_967_297_u64 ? 49 : 48)
  LibC.putchar(59)
end

report_numeric(forward_int_return)
report_numeric(forward_float_return)
report_numeric(forward_number_uint_return)
report_numeric(forward_number_float_return)
report_numeric(NumericReturnOrderA.int_call)
report_numeric(NumericReturnOrderA.float_call)
report_numeric(NumericReturnOrderA.number_float_call)
report_numeric(NumericReturnOrderB.number_float_call)
report_numeric(NumericReturnOrderB.float_call)
report_numeric(NumericReturnOrderB.int_call)
only_pending_uint64(pending_bottom_or_uint64)
only_pending_uint64(pending_redefined_int)
only_pending_uint64(forward_pending_redefined_int)
LibC.putchar(10)
NUMERIC_RETURN_FIXTURE

cat >"$WORK/abstract_numeric_tag_value.expected.stdout" <<'NUMERIC_RETURN_FIXTURE'
U1;F1;U1;F1;U1;F1;F1;F1;F1;U1;U1;U1;U1;
NUMERIC_RETURN_FIXTURE

cat >"$WORK/wrong_float32_for_int.cr" <<'NUMERIC_RETURN_FIXTURE'
def invalid_abstract_int_return : Int
  1.25_f32
end

invalid_abstract_int_return
NUMERIC_RETURN_FIXTURE

cat >"$WORK/unreachable_float32_for_int.cr" <<'NUMERIC_RETURN_FIXTURE'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def invalid_unreachable_abstract_int_return : Int
  LibC.exit(0)
  1.25_f32
end

# Demand the body: Crystal does not type-check unused definitions.
invalid_unreachable_abstract_int_return
NUMERIC_RETURN_FIXTURE

compile_positive() {
  local stage="$1"
  local compiler="$2"
  local output="$WORK/$stage.positive.bin"
  local -a args
  if [[ "$stage" == original ]]; then
    args=(build "$WORK/abstract_numeric_tag_value.cr" --single-module --no-debug -o "$output")
    if [[ "$(uname -s)" == Darwin ]]; then
      args+=(--link-flags=-fuse-ld=/usr/bin/ld)
    fi
  else
    args=("$WORK/abstract_numeric_tag_value.cr" -o "$output" --no-debug --no-ast-cache --no-llvm-cache)
  fi
  if [[ -n "${CRYSTAL_PATH:-}" ]]; then
    env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$WORK/$stage.cache" "$SAFE" "$compiler" 120 8192 "${args[@]}" >"$WORK/$stage.positive.compile.log" 2>&1
  else
    env CRYSTAL_CACHE_DIR="$WORK/$stage.cache" "$SAFE" "$compiler" 120 8192 "${args[@]}" >"$WORK/$stage.positive.compile.log" 2>&1
  fi
}

run_positive() {
  local stage="$1"
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 30 1024 "$WORK/$stage.positive.bin" "$WORK/$stage.positive.stderr" >"$WORK/$stage.positive.stdout" 2>"$WORK/$stage.positive.run.log"
  test ! -s "$WORK/$stage.positive.stderr"
  cmp "$WORK/abstract_numeric_tag_value.expected.stdout" "$WORK/$stage.positive.stdout"
}

expect_rejected() {
  local stage="$1"
  local compiler="$2"
  local case_name="$3"
  local output="$WORK/$stage.$case_name.bin"
  local -a args
  if [[ "$stage" == original ]]; then
    args=(build "$WORK/$case_name.cr" --single-module --no-debug -o "$output")
    if [[ "$(uname -s)" == Darwin ]]; then
      args+=(--link-flags=-fuse-ld=/usr/bin/ld)
    fi
  else
    args=("$WORK/$case_name.cr" -o "$output" --no-debug --no-ast-cache --no-llvm-cache)
  fi
  local status=0
  if [[ -n "${CRYSTAL_PATH:-}" ]]; then
    env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$WORK/$stage.cache" "$SAFE" "$compiler" 120 8192 "${args[@]}" >"$WORK/$stage.$case_name.compile.log" 2>&1 || status=$?
  else
    env CRYSTAL_CACHE_DIR="$WORK/$stage.cache" "$SAFE" "$compiler" 120 8192 "${args[@]}" >"$WORK/$stage.$case_name.compile.log" 2>&1 || status=$?
  fi
  if [[ "$status" != 1 || -e "$output" ]]; then
    cat "$WORK/$stage.$case_name.compile.log" >&2
    echo "FAIL $stage: expected source rejection (rc=1) without an executable" >&2
    return 1
  fi
  rg -q 'Float32' "$WORK/$stage.$case_name.compile.log"
  rg -q 'Int' "$WORK/$stage.$case_name.compile.log"
}

# Qualify fixture syntax, expected tags and the rejection against pristine Crystal first.
compile_positive original "$ORIGINAL"
run_positive original
expect_rejected original "$ORIGINAL" wrong_float32_for_int
expect_rejected original "$ORIGINAL" unreachable_float32_for_int

compile_positive candidate "$CANDIDATE"
run_positive candidate
expect_rejected candidate "$CANDIDATE" wrong_float32_for_int
expect_rejected candidate "$CANDIDATE" unreachable_float32_for_int

printf 'PASS: abstract numeric tags, values, NoReturn, redefinition and invalid-return rejection\n'
