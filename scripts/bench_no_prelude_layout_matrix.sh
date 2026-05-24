#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V2_COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
ORIG_COMPILER="${2:-crystal}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cv2_layout_matrix.XXXXXX")"

cleanup() {
  if [[ "${KEEP_LAYOUT_TMP:-0}" == "1" ]]; then
    echo "[bench-layout] kept tmp: $TMP_DIR" >&2
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$V2_COMPILER" ]]; then
  echo "usage: $0 <v2-compiler> [original-crystal]" >&2
  echo "missing executable v2 compiler: $V2_COMPILER" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "layout matrix currently requires Darwin mach_absolute_time()" >&2
  exit 2
fi

now_ms() {
  perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000'
}

file_size() {
  if [[ -f "$1" ]]; then
    stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

stdout_payload() {
  awk '
    /^=== STDOUT ===$/ { in_stdout = 1; next }
    /^=== STDERR ===$/ { in_stdout = 0 }
    in_stdout && NF { line = $0 }
    END { print line }
  ' "$1"
}

common_prefix() {
  cat <<'CR'
lib BenchLibC
  fun write(fd : Int32, buf : Void*, count : UInt64) : Int64
  fun bench_mach_absolute_time = mach_absolute_time : UInt64
  fun exit(code : Int32) : NoReturn
end

def bench_now_ticks : UInt64
  BenchLibC.bench_mach_absolute_time
end

def emit_byte(byte : UInt8) : Nil
  buf = Pointer(UInt8).malloc(1)
  buf[0] = byte
  BenchLibC.write(1, buf.as(Void*), 1_u64)
end

def emit_u64_digits(value : UInt64) : Nil
  buf = Pointer(UInt8).malloc(32)
  idx = 32
  v = value
  if v == 0_u64
    idx -= 1
    buf[idx] = 48_u8
  else
    while v > 0_u64
      digit = (v % 10_u64).to_u8
      idx -= 1
      buf[idx] = 48_u8 + digit
      v = v // 10_u64
    end
  end
  BenchLibC.write(1, (buf + idx).as(Void*), (32 - idx).to_u64)
end

def emit_result(checksum : UInt64, elapsed_ticks : UInt64) : Nil
  emit_u64_digits(checksum)
  emit_byte(9_u8)
  emit_u64_digits(elapsed_ticks)
  emit_byte(10_u8)
end
CR
}

write_case() {
  local name="$1"
  local src="$TMP_DIR/$name.cr"
  common_prefix >"$src"
  case "$name" in
    scalar_i64_loop)
      cat >>"$src" <<'CR'
acc = 0_u64
i = 0_u64
bench_start = bench_now_ticks
while i < 2_000_000_u64
  acc = acc &+ ((i &* 3_u64) ^ (i >> 1))
  i += 1_u64
end
bench_elapsed = bench_now_ticks - bench_start
emit_result(acc, bench_elapsed)
BenchLibC.exit(0)
CR
      ;;
    struct_local_loop)
      cat >>"$src" <<'CR'
struct Pair
  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

acc = 0_i64
i = 0_i64
bench_start = bench_now_ticks
while i < 1_000_000_i64
  pair = Pair.new(i, i + 7_i64)
  acc += pair.sum
  i += 1_i64
end
bench_elapsed = bench_now_ticks - bench_start
emit_result(acc.to_u64, bench_elapsed)
BenchLibC.exit(0)
CR
      ;;
    nested_struct_loop)
      cat >>"$src" <<'CR'
struct Pair
  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

struct Quad
  def initialize(@a : Pair, @b : Pair)
  end

  def sum : Int64
    @a.sum + @b.sum
  end
end

acc = 0_i64
i = 0_i64
bench_start = bench_now_ticks
while i < 700_000_i64
  q = Quad.new(Pair.new(i, i + 1_i64), Pair.new(i + 2_i64, i + 3_i64))
  acc += q.sum
  i += 1_i64
end
bench_elapsed = bench_now_ticks - bench_start
emit_result(acc.to_u64, bench_elapsed)
BenchLibC.exit(0)
CR
      ;;
    pointer_struct_stride)
      cat >>"$src" <<'CR'
struct Pair
  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

ptr = Pointer(Pair).malloc(4096)
i = 0
while i < 4096
  ptr[i] = Pair.new(i.to_i64, (i * 2).to_i64)
  i += 1
end
acc = 0_i64
round = 0
bench_start = bench_now_ticks
while round < 500
  i = 0
  while i < 4096
    acc += ptr[i].sum
    i += 1
  end
  round += 1
end
bench_elapsed = bench_now_ticks - bench_start
emit_result(acc.to_u64, bench_elapsed)
BenchLibC.exit(0)
CR
      ;;
    pointer_tuple_stride)
      cat >>"$src" <<'CR'
ptr = Pointer(Tuple(Int64, Int64)).malloc(4096)
i = 0
while i < 4096
  ptr[i] = {i.to_i64, (i * 2).to_i64}
  i += 1
end
acc = 0_i64
round = 0
bench_start = bench_now_ticks
while round < 500
  i = 0
  while i < 4096
    t = ptr[i]
    acc += t[0] + t[1]
    i += 1
  end
  round += 1
end
bench_elapsed = bench_now_ticks - bench_start
emit_result(acc.to_u64, bench_elapsed)
BenchLibC.exit(0)
CR
      ;;
    pointer_nilable_struct_union)
      cat >>"$src" <<'CR'
struct Pair
  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

ptr = Pointer(Pair | Nil).malloc(4096)
i = 0
while i < 4096
  if (i & 1) == 0
    ptr[i] = Pair.new(i.to_i64, (i * 2).to_i64)
  else
    ptr[i] = nil
  end
  i += 1
end
acc = 0_i64
round = 0
bench_start = bench_now_ticks
while round < 500
  i = 0
  while i < 4096
    if pair = ptr[i]
      acc += pair.sum
    else
      acc -= 1_i64
    end
    i += 1
  end
  round += 1
end
bench_elapsed = bench_now_ticks - bench_start
emit_result(acc.to_u64, bench_elapsed)
BenchLibC.exit(0)
CR
      ;;
    pointer_mixed_struct_int_union)
      cat >>"$src" <<'CR'
struct Pair
  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

ptr = Pointer(Pair | Int64).malloc(4096)
i = 0
while i < 4096
  if (i & 1) == 0
    ptr[i] = Pair.new(i.to_i64, (i * 2).to_i64)
  else
    ptr[i] = i.to_i64
  end
  i += 1
end
acc = 0_i64
round = 0
bench_start = bench_now_ticks
while round < 500
  i = 0
  while i < 4096
    value = ptr[i]
    if value.is_a?(Pair)
      acc += value.sum
    else
      acc += value
    end
    i += 1
  end
  round += 1
end
bench_elapsed = bench_now_ticks - bench_start
emit_result(acc.to_u64, bench_elapsed)
BenchLibC.exit(0)
CR
      ;;
    yield_struct_loop)
      cat >>"$src" <<'CR'
struct Pair
  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

def each_pair(limit : Int64)
  i = 0_i64
  while i < limit
    yield Pair.new(i, i + 3_i64)
    i += 1_i64
  end
end

acc = 0_i64
bench_start = bench_now_ticks
each_pair(1_000_000_i64) do |pair|
  acc += pair.sum
end
bench_elapsed = bench_now_ticks - bench_start
emit_result(acc.to_u64, bench_elapsed)
BenchLibC.exit(0)
CR
      ;;
    class_alloc_loop)
      cat >>"$src" <<'CR'
class BenchBox
  def initialize(@x : Int64, @y : Int64)
  end

  def sum : Int64
    @x + @y
  end
end

acc = 0_i64
i = 0_i64
bench_start = bench_now_ticks
while i < 500_000_i64
  box = BenchBox.new(i, i + 5_i64)
  acc += box.sum
  i += 1_i64
end
bench_elapsed = bench_now_ticks - bench_start
emit_result(acc.to_u64, bench_elapsed)
BenchLibC.exit(0)
CR
      ;;
    *)
      echo "unknown case: $name" >&2
      return 1
      ;;
  esac
}

compile_and_run() {
  local compiler_kind="$1"
  local compiler="$2"
  local name="$3"
  local src="$TMP_DIR/$name.cr"
  local bin="$TMP_DIR/${name}_${compiler_kind}"
  local compile_log="$TMP_DIR/${name}_${compiler_kind}.compile.log"
  local run_log="$TMP_DIR/${name}_${compiler_kind}.run.log"
  local start end compile_ms run_ms compile_rc run_rc payload checksum internal_ticks size

  start="$(now_ms)"
  set +e
  if [[ "$compiler_kind" == "v2" ]]; then
    "$ROOT_DIR/scripts/run_safe.sh" "$compiler" 120 4096 \
      "$src" --no-prelude --release -o "$bin" >"$compile_log" 2>&1
  else
    "$ROOT_DIR/scripts/run_safe.sh" "$compiler" 120 4096 \
      build "$src" --release -o "$bin" >"$compile_log" 2>&1
  fi
  compile_rc=$?
  set -e
  end="$(now_ms)"
  compile_ms=$((end - start))
  size="$(file_size "$bin")"

  if [[ $compile_rc -ne 0 || ! -x "$bin" ]]; then
    printf '%s\t%s\tcompile_fail\t%s\t-\t%s\t-\t-\t-\t%s\n' \
      "$name" "$compiler_kind" "$compile_ms" "$size" "$compile_rc"
    return
  fi

  start="$(now_ms)"
  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$bin" 20 1024 >"$run_log" 2>&1
  run_rc=$?
  set -e
  end="$(now_ms)"
  run_ms=$((end - start))
  payload="$(stdout_payload "$run_log")"
  checksum="$(printf '%s' "$payload" | awk -F '\t' '{ print $1 }')"
  internal_ticks="$(printf '%s' "$payload" | awk -F '\t' '{ print $2 }')"
  [[ -n "$checksum" ]] || checksum="-"
  [[ -n "$internal_ticks" ]] || internal_ticks="-"

  if [[ $run_rc -ne 0 ]]; then
    printf '%s\t%s\trun_fail\t%s\t%s\t%s\t%s\t%s\t-\t%s\n' \
      "$name" "$compiler_kind" "$compile_ms" "$run_ms" "$size" "$checksum" "$internal_ticks" "$run_rc"
  else
    printf '%s\t%s\tok\t%s\t%s\t%s\t%s\t%s\t-\t0\n' \
      "$name" "$compiler_kind" "$compile_ms" "$run_ms" "$size" "$checksum" "$internal_ticks"
  fi
}

CASES=(
  scalar_i64_loop
  struct_local_loop
  nested_struct_loop
  pointer_struct_stride
  pointer_tuple_stride
  pointer_nilable_struct_union
  pointer_mixed_struct_int_union
  yield_struct_loop
  class_alloc_loop
)

printf 'case\tcompiler\tstatus\tcompile_ms\trun_ms\tbinary_bytes\tchecksum\tinternal_ticks\tnote\trc\n'
for name in "${CASES[@]}"; do
  write_case "$name"
  compile_and_run "original" "$ORIG_COMPILER" "$name"
  compile_and_run "v2" "$V2_COMPILER" "$name"
done
