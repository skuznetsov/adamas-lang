#!/usr/bin/env bash
# Compare constructor default/new routing against Crystal, including String's
# Slice(UInt8) constructor and controls that exercise ordinary allocator paths.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-$ROOT_DIR/../crystal/src}"
LINK_FLAGS="${CRYSTAL_LINK_FLAGS:-${ADAMAS_EXTRA_LINK_FLAGS:-}}"

[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: $0 <candidate-compiler> (set ORIGINAL_CRYSTAL_BIN and CRYSTAL_PATH as needed)" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/constructor-default-new.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/constructor_default_new.cr" <<'CRYSTAL'
lib LibC
  fun putchar(c : Int32) : Int32
end

def emit_text(text : String) : Nil
  text.each_byte { |byte| LibC.putchar(byte.to_i) }
end

def emit_decimal(value : Int32) : Nil
  LibC.putchar(48 + value // 100)
  LibC.putchar(48 + (value // 10) % 10)
  LibC.putchar(48 + value % 10)
end

def emit_string(label : String, value : String) : Nil
  emit_text(label)
  LibC.putchar(61) # =
  emit_decimal(value.bytesize)
  LibC.putchar(58) # :
  first = true
  value.each_byte do |byte|
    LibC.putchar(44) unless first # ,
    first = false
    emit_decimal(byte.to_i)
  end
  LibC.putchar(10)
end

class PlainGeneratedAllocatorControl
  getter value : Int32

  def initialize(@value : Int32)
  end
end

class ExplicitNamedNewControl
  getter value : Int32
  getter enabled : Bool

  def initialize
    @value = 0
    @enabled = false
  end

  def configure(value : Int32, enabled : Bool) : Nil
    @value = value
    @enabled = enabled
  end

  def self.new(value : Int32, *, enabled : Bool = false) : self
    LibC.putchar(78) # N: explicit source new body was selected
    instance = new
    instance.configure(value, enabled)
    instance
  end
end

with_nul = Bytes.new(3)
with_nul[0] = 65_u8
with_nul[1] = 0_u8
with_nul[2] = 66_u8
empty = Bytes.new(0)

emit_string("nul_omitted", String.new(with_nul))
emit_string("nul_false", String.new(with_nul, truncate_at_null: false))
emit_string("nul_true", String.new(with_nul, truncate_at_null: true))
emit_string("empty_omitted", String.new(empty))
emit_string("empty_false", String.new(empty, truncate_at_null: false))
emit_string("empty_true", String.new(empty, truncate_at_null: true))

plain = PlainGeneratedAllocatorControl.new(68)
LibC.putchar(112) # p
LibC.putchar(108) # l
LibC.putchar(97)  # a
LibC.putchar(105) # i
LibC.putchar(110) # n
LibC.putchar(61)
LibC.putchar(plain.value)
LibC.putchar(10)

disabled = ExplicitNamedNewControl.new(67, enabled: false)
LibC.putchar(disabled.value)
LibC.putchar(disabled.enabled ? 84 : 70)
LibC.putchar(10)
enabled = ExplicitNamedNewControl.new(69, enabled: true)
LibC.putchar(enabled.value)
LibC.putchar(enabled.enabled ? 84 : 70)
LibC.putchar(10)
CRYSTAL

cat >"$WORK_DIR/expected.stdout" <<'EXPECTED'
nul_omitted=003:065,000,066
nul_false=003:065,000,066
nul_true=001:065
empty_omitted=000:
empty_false=000:
empty_true=000:
plain=D
NCF
NET
EXPECTED

mkdir "$WORK_DIR/original.cache"
original_build_log="$WORK_DIR/original.build.log"
candidate_build_log="$WORK_DIR/candidate.build.log"
original_args=(build "$WORK_DIR/constructor_default_new.cr" -o "$WORK_DIR/original.bin" --no-debug)
if [[ -n "$LINK_FLAGS" ]]; then
  original_args+=("--link-flags=$LINK_FLAGS")
fi
if ! env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.cache" \
  "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 "${original_args[@]}" \
  >"$original_build_log" 2>&1; then
  cat "$original_build_log" >&2
  exit 1
fi

run_safe_capture() {
  local binary="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 15 1024 \
    >"$stdout_file" 2>"$stderr_file"; then
    cat "$stderr_file" >&2
    return 1
  fi
  if ! grep -Fq '[EXIT: 0]' "$stderr_file"; then
    cat "$stderr_file" >&2
    return 1
  fi
}

run_safe_capture "$WORK_DIR/original.bin" "$WORK_DIR/original.stdout" "$WORK_DIR/original.run.log"
diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/original.stdout"

if ! env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.cache" \
  ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" \
  "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/constructor_default_new.cr" \
  --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/candidate.bin" \
  >"$candidate_build_log" 2>&1; then
  cat "$candidate_build_log" >&2
  exit 1
fi
run_safe_capture "$WORK_DIR/candidate.bin" "$WORK_DIR/candidate.stdout" "$WORK_DIR/candidate.run.log"

diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/candidate.stdout"
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"

printf 'PASS: String Slice constructor defaults and explicit-new/allocator controls match Crystal\n'
