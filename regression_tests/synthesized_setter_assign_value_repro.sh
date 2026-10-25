#!/usr/bin/env bash
# `obj.field = v` through a synthesized accessor (no registered setter
# DefNode) lowered to a direct FieldSet and evaluated to the store, typed as
# the field. Crystal evaluates the assignment to `v`, so a module/nilable
# field widened the result: prelude hello (1.22.1 stdlib) rejected
# `Parallel.default : self` = `Fiber.current.execution_context = new(...)`
# as returning ExecutionContext.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/synthesized-setter-assign-value.XXXXXX")"
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

write_case self_return_through_setter '
class Object
  macro setter(*names)
    {% for name in names %}
      def {{name.var.id}}=(@{{name.var.id}} : {{name.type}})
      end
    {% end %}
  end
end

module Ex
end

class Fb

  @@cur = Fb.new

  def self.current : Fb
    @@cur
  end

  @ctx : Ex?

  setter ctx : Ex
end

class Par
  include Ex

  def initialize(@n : Int32)
  end

  def n : Int32
    @n
  end

  def self.default(m : Int32) : self
    Fb.current.ctx = new(m)
  end
end

LibC.exit(Par.default(41).n)'
write_case assignment_value_keeps_arg_type '
class Object
  macro setter(*names)
    {% for name in names %}
      def {{name.var.id}}=(@{{name.var.id}} : {{name.type}})
      end
    {% end %}
  end
end

module Ex
end

class Fb

  @@cur = Fb.new

  def self.current : Fb
    @@cur
  end

  @ctx : Ex?

  setter ctx : Ex
end

class Par
  include Ex

  def initialize(@n : Int32)
  end

  def n : Int32
    @n
  end

end

p = (Fb.current.ctx = Par.new(42))
LibC.exit(p.n)'

CASES=(self_return_through_setter:41 assignment_value_keeps_arg_type:42)

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
  printf '%d synthesized setter assignment value case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'synthesized setter assignment value cases passed\n'
