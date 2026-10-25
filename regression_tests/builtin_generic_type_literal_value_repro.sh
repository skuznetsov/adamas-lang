#!/usr/bin/env bash
# A builtin generic type literal used as a value (`Tuple(Int32, UInt8)` passed
# to `type : F.class`) was typed Void because Tuple instances have no
# class_info, so F stayed unbound: `Bx(F)` degraded to Pointer or a phantom
# instance (prelude hello, 1.22.1 Crystal::DWARF memory_map).
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/builtin-generic-literal.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end
CR

write_case() {
  local name="$1" body="$2"
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$body"; } > "$WORK_DIR/$name.cr"
}

write_case tuple_literal_binds_forall '
struct Bx(T)
  def initialize(@n : Int32)
  end

  def code : Int32
    t = T
    @n
  end
end

class Rd
  private def mm(n, type : F.class) forall F
    Bx(F).new(n).code
  end

  def run : Int32
    mm(51, Tuple(Int32, Int32, UInt8))
  end
end

LibC.exit(Rd.new.run)'
write_case tuple_literal_binds_forall_inline_yield '
struct Bx(T)
  def initialize(@n : Int32)
  end

  def code : Int32
    t = T
    @n
  end
end

class Rd
  private def mm(n, type : F.class, &) forall F
    b = Bx(F).new(n)
    yield b
  end

  def run : Int32
    mm(51, Tuple(Int32, Int32, UInt8)) { |b| b.code }
  end
end

LibC.exit(Rd.new.run)'
write_case tuple_literal_binds_forall_public '
struct Bx(T)
  def initialize(@n : Int32)
  end

  def code : Int32
    t = T
    @n
  end
end

class Rd
  def mm(n, type : F.class, &) forall F
    b = Bx(F).new(n)
    yield b
  end

  def run : Int32
    mm(51, Tuple(Int32, Int32, UInt8)) { |b| b.code }
  end
end

LibC.exit(Rd.new.run)'

CASES=(tuple_literal_binds_forall:51 tuple_literal_binds_forall_inline_yield:51 tuple_literal_binds_forall_public:51)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d builtin generic type literal value case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'builtin generic type literal value cases passed\n'
