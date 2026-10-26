#!/usr/bin/env bash
# `@var : Type` and `@@var : Type` are declarations wherever a type
# declaration may appear, as in original Crystal's
# new_node_check_type_declaration. The parser recognized them only directly in
# a class/module/lib body, but macro output (getter!'s `@{{name}}?`) is parsed
# as a standalone program: `@ab : Arr(Abbrev)?` became `@ab` followed by the
# expression `Arr(Abbrev)?`, whose `?` swallowed the next `def ab?` header as a
# ternary. The class pass then paired `@ab` with a stray `end` identifier and
# typed the ivar as `end`, so prelude hello failed with "undefined method '[]?'
# for Crystal::DWARF::Info::end" (dwarf/info.cr `property! abbreviations :
# Array(Abbrev)`). A ternary `c ? @a : @b` must stay a ternary. Positive cases
# exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-ivar-declaration.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  cat > "$WORK_DIR/$name.cr" <<'HEAD'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class NilAssertionError
  def initialize(@message : String)
  end
end

def raise(e : NilAssertionError) : NoReturn
  LibC.exit(3)
end

class Object
  def try(&)
    yield self
  end

  macro getter!(*names)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        @{{name}}?
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}}? {% if type %} : {{type}}? {% end %}
        @{{var_name}}
      end

      def {{var_name}} {% if type %} : {{type}} {% end %}
        if (%value = @{{var_name}}).nil?
          ::raise ::NilAssertionError.new("{{@type.id}}{{"#".id}}{{var_name}} cannot be nil")
        else
          %value
        end
      end

    {% end %}
  end

  macro class_getter!(*names)
    {% for name in names %}
      @@{{name}}?

      def self.{{name.var.id}}? : {{name.type}}?
        @@{{name.var.id}}
      end
    {% end %}
  end
end

struct Nil
  def try(&)
    self
  end
end

class Abbrev
  def initialize(@code : Int32)
  end

  def code : Int32
    @code
  end
end

class Arr(T)
  def initialize(@a : T)
  end

  def []?(i : UInt64) : T?
    i == 1_u64 ? @a : nil
  end
end

HEAD
  printf '%s\n' "$body" >> "$WORK_DIR/$name.cr"
}

write_case generic_getter_bang 'class Info
  getter! ab : Arr(Abbrev)

  def initialize(@ab : Arr(Abbrev)?)
  end

  def run : Int32
    x = @ab
    if x
      y = x[1_u64]?
      y ? y.code : 1
    else
      0
    end
  end
end

LibC.exit(Info.new(Arr.new(Abbrev.new(42))).run)'
write_case struct_try_shorthand 'struct Info
  getter! abbreviations : Arr(Abbrev)

  def initialize(a : Arr(Abbrev)?)
    @abbreviations = a
  end

  def each(&)
    code = 2_u64
    if abbrev = @abbreviations.try &.[code &- 1]?
      yield abbrev.code
    else
      yield 0
    end
  end
end

Info.new(Arr.new(Abbrev.new(42))).each { |v| LibC.exit(v) }'
write_case generic_class_var 'class Info
  class_getter! cache : Arr(Abbrev)

  def self.fill : Nil
    @@cache = Arr.new(Abbrev.new(42))
  end
end

Info.fill
c = Info.cache?
y = c ? c[1_u64]? : nil
LibC.exit(y ? y.code : 1)'
write_case ternary_ivars 'class Pick
  def initialize(@a : Int32, @b : Int32)
  end

  def run(c : Bool) : Int32
    c ? @a : @b
  end
end

LibC.exit(Pick.new(40, 2).run(true) &+ Pick.new(40, 2).run(false))'

POSITIVE=(generic_getter_bang struct_try_shorthand generic_class_var ternary_ivars)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${POSITIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run exit %s)\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
