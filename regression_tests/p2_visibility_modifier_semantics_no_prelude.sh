#!/usr/bin/env bash
# No-prelude guard: visibility modifiers around non-accessor declarations must
# follow Crystal top-level semantics instead of being silently unwrapped.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_visibility_modifier_semantics_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

compile_ok() {
  local name="$1"
  local src="$TMP_DIR/$name.cr"
  local out="$TMP_DIR/$name"
  local log="$TMP_DIR/$name.log"
  cat >"$src"
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
    "$src" --no-prelude --emit hir --no-link -o "$out" >"$log" 2>&1
}

compile_fail_with() {
  local name="$1"
  local expected="$2"
  local src="$TMP_DIR/$name.cr"
  local out="$TMP_DIR/$name"
  local log="$TMP_DIR/$name.log"
  cat >"$src"

  set +e
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
    "$src" --no-prelude --emit hir --no-link -o "$out" >"$log" 2>&1
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "p2 visibility modifier regression: $name compiled unexpectedly" >&2
    cat "$log" >&2
    exit 1
  fi

  if ! grep -Fq "$expected" "$log"; then
    echo "p2 visibility modifier regression: $name missing diagnostic: $expected" >&2
    cat "$log" >&2
    exit 1
  fi
}

compile_ok private_type <<'CR'
class Object
end

private class Hidden
  def value : Int32
    1
  end
end

Hidden.new.value
CR

compile_ok private_constant <<'CR'
class Object
end

private VALUE = 1
VALUE
CR

compile_ok private_macro <<'CR'
class Object
end

private macro hidden
end
CR

compile_ok private_protected_abstract_defs <<'CR'
class Object
end

abstract class Base
  private abstract def hidden : Int32
  protected abstract def visible_to_subtypes : Int32
end
CR

compile_fail_with protected_type "can only use 'private' for types" <<'CR'
class Object
end

protected class Hidden
end
CR

compile_fail_with protected_constant "can only use 'private' for constants" <<'CR'
class Object
end

protected VALUE = 1
VALUE
CR

compile_fail_with protected_macro "can only use 'private' for macros" <<'CR'
class Object
end

protected macro hidden
end
CR

compile_fail_with private_literal "can't apply visibility modifier" <<'CR'
class Object
end

private 1
CR

echo "p2_visibility_modifier_semantics_no_prelude_ok"
