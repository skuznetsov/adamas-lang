#!/usr/bin/env bash
# A yielding method with `forall F` was inlined without binding F from the
# call arguments (`type : F.class`, `x : F`): the inlined body saw `F` as an
# undefined constant, or built a phantom `Bx(F)` whose methods failed on T.
# Prelude hello (1.22.1 stdlib) hit it through
# Crystal::DWARF memory_map(bytesize, type : F.class, &) forall F.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inline-yield-forall.XXXXXX")"
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

write_case bare_forall_in_inlined_body '
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
    t = F
    yield Bx(Int32).new(n)
  end

  def run : Int32
    mm(51, Int32) { |b| b.code }
  end
end

LibC.exit(Rd.new.run)'
write_case forall_value_arg_generic '
struct Bx(T)
  def initialize(@n : Int32)
  end

  def code : Int32
    t = T
    @n
  end
end

class Rd
  private def mm(n, x : F, &) forall F
    b = Bx(F).new(n)
    yield b
  end

  def run : Int32
    mm(51, 7) { |b| b.code }
  end
end

LibC.exit(Rd.new.run)'
write_case forall_class_arg_generic '
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
    mm(51, Int32) { |b| b.code }
  end
end

LibC.exit(Rd.new.run)'

CASES=(bare_forall_in_inlined_body:51 forall_value_arg_generic:51 forall_class_arg_generic:51)

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
  printf '%d inline-yield method forall case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'inline-yield method forall cases passed\n'
