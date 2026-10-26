#!/usr/bin/env bash
# A struct member access is typed by the member's def, not by a same-named
# ivar. Constructor arguments are typed from the AST before lowering, and that
# inference returned a struct's `@size : UInt64?` for `s.size` whenever the
# ivar existed, so getter!'s raise-on-nil `def size : UInt64?` (never nil in
# Crystal's typing) specialized `Str.new(s.size)` for `Nil | UInt64`. Prelude
# hello failed with "no overload matches Slice(UInt8).new for argument types
# (Nil | Int32 | Int64 | UInt64)" in Crystal::DWARF::Strings#initialize, called
# as `Strings.new(io, sh.offset, sh.size)` on a MachO::Section64 (property!).
# A native getter (no DefNode) keeps its ivar type even when an ancestor
# declares a same-named def (Hash::Entry#hash vs Object#hash). A def that can
# return nil keeps its union and stays rejected. Positive cases
# exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/struct-member-def-type.XXXXXX")"

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
  LibC.exit(42)
end

class Object
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

  macro property!(*names)
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

      def {{var_name}}=(@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end
end

struct Sec
  property! size : UInt64
  property! offset : UInt32
  @plain : UInt64 = 40_u64
  @raw : UInt64 = 40_u64
  @maybe : UInt64? = 40_u64

  def initialize
  end

  def plain : UInt64
    @plain
  end

  def raw
    @raw
  end

  def maybe : UInt64?
    @maybe
  end
end

def take(x : UInt64) : Int32
  x.to_i32! &+ 2
end

struct Str
  @v : Int32

  def initialize(@offset : UInt32 | UInt64, size)
    @v = take(size)
  end

  def v
    @v
  end
end

class K
  @v : Int32

  def initialize(size)
    @v = take(size)
  end

  def v
    @v
  end
end

def sec : Sec
  s = Sec.new
  s.size = 40_u64
  s.offset = 1_u32
  s
end
HEAD
  printf '\n%s\n' "$body" >> "$WORK_DIR/$name.cr"
}

write_case bang_struct_ctor 'LibC.exit(Str.new(sec.offset, sec.size).v)'
write_case bang_class_ctor 's = sec
LibC.exit(K.new(s.size).v)'
write_case bang_block_ctor 'def with_sec(&)
  yield sec
end

r = with_sec { |sh| Str.new(sh.offset, sh.size) }
LibC.exit(r.v)'
write_case plain_getter_ctor 'LibC.exit(K.new(sec.plain).v)'
write_case untyped_def_ctor 'LibC.exit(K.new(sec.raw).v)'
# A native getter has no DefNode; the return lookup then reaches an
# ancestor's def of the same name, which must not override the ivar.
write_case native_getter_over_ancestor 'struct Value
end

struct Struct
end

class Object
  macro getter(*names, &block)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        {% if block %}
          @{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
        {% else %}
          @{{name}}
        {% end %}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}} {% if type %} : {{type}} {% end %}
        {% if block %}
          if (%value = @{{var_name}}).nil?
            @{{var_name}} = {{yield}}
          else
            %value
          end
        {% else %}
          @{{var_name}}
        {% end %}
      end

    {% end %}
  end

  def tag : UInt64
    7_u64
  end
end

struct Ent
  getter key, tag

  def initialize(@tag : UInt32, @key : Int32)
  end
end

def get_ent : Ent
  Ent.new(40_u32, 1)
end

entry = get_ent
e = Ent.new(entry.tag, 2)
LibC.exit(e.tag.to_i32! &+ e.key)'
# Negative: the def can return nil, so take(UInt64) gets `UInt64?`.
write_case nilable_def_rejected 'LibC.exit(K.new(sec.maybe).v)'

POSITIVE=(bang_struct_ctor bang_class_ctor bang_block_ctor plain_getter_ctor untyped_def_ctor
  native_getter_over_ancestor)
NEGATIVE=(nilable_def_rejected)

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
  for name in "${NEGATIVE[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
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

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "0" ]]; then
    printf 'FAIL %s (accepted)\n' "$name"
    failures=$((failures + 1))
  else
    printf 'PASS %s (rejected)\n' "$name"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
