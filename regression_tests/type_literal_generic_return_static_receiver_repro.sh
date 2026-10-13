#!/usr/bin/env bash
# Returning a generic type parameter from a class method must preserve the
# type-literal receiver so the next call selects a class method, not an
# instance method with the same name.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/type_literal_generic_return.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/repro.cr" <<'CR'
struct TypeLiteralGenericReturnProbe(T)
  def self.type
    T
  end
end

struct TypeLiteralMacroConditionalReturnProbe(X)
  def self.type
    {% if X.union? %}
      {{ raise("Union is not supported by this probe") }}
    {% else %}
      X
    {% end %}
  end
end

struct TypeLiteralMacroInstanceReturnProbe(X)
  def self.pick
    {% if X.union? %}
      X
    {% else %}
      X.new
    {% end %}
  end
end

struct TypeLiteralMacroInstanceMarkerProbe
  def self.zero : Int32
    47
  end

  def zero : Int32
    53
  end
end

def type_literal_zero_from_argument(reflect)
  selected_type = reflect.type
  selected_type.zero
end

struct TypeLiteralClassInstanceZeroProbe
  def self.zero : Int32
    17
  end

  def zero : Int32
    29
  end
end

class TypeLiteralAliasFactory(T)
  def self.pick(value : Int32)
    T
  end

  def self.pick(value : String)
    T.new
  end
end

class TypeLiteralAliasRuntimeFirstProbe
  def self.zero : Int32
    17
  end

  def zero : Int32
    29
  end
end

class TypeLiteralAliasLiteralFirstProbe
  def self.zero : Int32
    31
  end

  def zero : Int32
    37
  end
end

int32_zero = TypeLiteralGenericReturnProbe(Int32).type.zero
float64_zero = TypeLiteralGenericReturnProbe(Float64).type.zero
int32_paren_zero = TypeLiteralGenericReturnProbe(Int32).type().zero
float64_paren_zero = TypeLiteralGenericReturnProbe(Float64).type().zero
macro_int32_zero = TypeLiteralMacroConditionalReturnProbe(Int32).type.zero
macro_float64_zero = TypeLiteralMacroConditionalReturnProbe(Float64).type.zero
macro_int32_local_zero = type_literal_zero_from_argument(TypeLiteralMacroConditionalReturnProbe(Int32))
macro_float64_local_zero = type_literal_zero_from_argument(TypeLiteralMacroConditionalReturnProbe(Float64))
macro_instance_zero = TypeLiteralMacroInstanceReturnProbe(TypeLiteralMacroInstanceMarkerProbe).pick.zero
direct_int32_zero = Int32.zero
class_zero = TypeLiteralGenericReturnProbe(TypeLiteralClassInstanceZeroProbe).type.zero
instance_zero = TypeLiteralClassInstanceZeroProbe.new.zero
runtime_first_instance = TypeLiteralAliasFactory(TypeLiteralAliasRuntimeFirstProbe).pick("runtime").zero
runtime_first_class = TypeLiteralAliasFactory(TypeLiteralAliasRuntimeFirstProbe).pick(1_i32).zero
literal_first_class = TypeLiteralAliasFactory(TypeLiteralAliasLiteralFirstProbe).pick(1_i32).zero
literal_first_instance = TypeLiteralAliasFactory(TypeLiteralAliasLiteralFirstProbe).pick("runtime").zero

LibC.exit(
  int32_zero == 0 &&
  float64_zero == 0.0 &&
  int32_paren_zero == 0 &&
  float64_paren_zero == 0.0 &&
  macro_int32_zero == 0 &&
  macro_float64_zero == 0.0 &&
  macro_int32_local_zero == 0 &&
  macro_float64_local_zero == 0.0 &&
  macro_instance_zero == 53 &&
  direct_int32_zero == 0 &&
  class_zero == 17 &&
  instance_zero == 29 &&
  runtime_first_instance == 29 &&
  runtime_first_class == 17 &&
  literal_first_class == 31 &&
  literal_first_instance == 37 ? 0 : 1
)
CR

if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/build.resources" \
    "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
    "$WORK_DIR/repro.cr" -o "$WORK_DIR/repro" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi

RUN_SAFE_RESOURCE_FILE="$WORK_DIR/run.resources" \
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "type-literal generic return failed (expected EXIT 0):" >&2
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi

echo type_literal_generic_return_static_receiver_repro_ok
