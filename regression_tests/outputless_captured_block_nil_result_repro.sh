#!/usr/bin/env bash
# `def initialize(&@func : Th ->)` (Thread in the 1.22.1 stdlib) stores
# `Proc(Th, Void)`, but nil_returning_proc_annotation? accepted only a `Nil`
# result, so a block whose body has a value materialized as `Proc(Th, Int32)`
# and the constructor raised "captured initializer Proc ABI conflict".
# An output-less block discards its value like `T -> Nil`.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/outputless-captured-block.XXXXXX")"
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

write_case zero_param_block '
class Th
  @r = 0

  def initialize(@name : Int32? = nil, &@func : Th ->)
  end

  def initialize
    @func = ->(t : Th) { }
  end

  def run : Int32
    @func.call(self)
    @r
  end

  def r=(@r : Int32)
  end
end

def loop5 : Int32
  5
end

x = Th.new(name: 1) { loop5 }
LibC.exit(x.run + 5)'
write_case value_block '
class Th
  @r = 0

  def initialize(@name : Int32? = nil, &@func : Th ->)
  end

  def initialize
    @func = ->(t : Th) { }
  end

  def run : Int32
    @func.call(self)
    @r
  end

  def r=(@r : Int32)
  end
end

def loop5 : Int32
  5
end

x = Th.new do |t|
  t.r = 7
  3
end
LibC.exit(x.run)'
write_case mixed_callsites '
class Th
  @r = 0

  def initialize(@name : Int32? = nil, &@func : Th ->)
  end

  def initialize
    @func = ->(t : Th) { }
  end

  def run : Int32
    @func.call(self)
    @r
  end

  def r=(@r : Int32)
  end
end

def loop5 : Int32
  5
end

x = Th.new(name: 1) { loop5 }
y = Th.new do |t|
  t.r = 7
  3
end
z = Th.new
LibC.exit(x.run + y.run + z.run)'

CASES=(zero_param_block:5 value_block:7 mixed_callsites:7)

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
  printf '%d output-less captured block case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'output-less captured block cases passed\n'
