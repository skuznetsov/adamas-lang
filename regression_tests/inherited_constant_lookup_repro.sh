#!/usr/bin/env bash
# A constant named without a path is looked up in the current type, then in
# its ancestors (superclasses and included modules), and only then in the
# enclosing namespaces (Crystal's Type#lookup_path_item). V2 skipped the
# ancestors, so stage 2 failed on hir.cr's `@must_alias_with_value : ValueId
# = NO_MUST_ALIAS`, an ivar default declared in `abstract class Value` and
# evaluated for each subclass, with "undefined constant NO_MUST_ALIAS".
# Ancestors' enclosing namespaces are not searched; that case must stay
# rejected. Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inherited-constant.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  cat > "$WORK_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

$body
CR
}

# Parent constant in an inherited ivar default (the stage 2 shape).
write_case ivar_default_from_parent "module M
  abstract class Value
    NONE = 7

    @alias_value : Int32 = NONE

    def alias_value
      @alias_value
    end
  end

  class Lit < Value
    def initialize(@id : Int32)
    end

    def id
      @id
    end
  end
end

LibC.exit(M::Lit.new(35).id &+ M::Lit.new(1).alias_value)"
# Parent constant read in a subclass method.
write_case method_from_parent "abstract class Base
  NONE = 7
end

class Lit < Base
  def get
    35 &+ NONE
  end
end

LibC.exit(Lit.new.get)"
# Constant of an included module, and of a module included by the parent.
write_case included_module "module Mx
  SEVEN = 7
end

module My
  THIRTY = 30
end

class Base
  include My
end

class Lit < Base
  include Mx

  def get
    5 &+ SEVEN &+ THIRTY
  end
end

LibC.exit(Lit.new.get)"
# Generic parent instance.
write_case generic_parent "class Base(T)
  NONE = 7
end

class Lit < Base(Int32)
  def get
    35 &+ NONE
  end
end

LibC.exit(Lit.new.get)"
# An ancestor's constant wins over the enclosing namespace's.
write_case ancestor_before_namespace "class Base
  K = 41
end

module W
  K = 1

  class Lit < Base
    def get
      K &+ 1
    end
  end
end

LibC.exit(W::Lit.new.get)"
# Negative: the parent's enclosing namespace is not searched.
write_case parent_namespace_rejected "module Outer
  NS = 7

  class Base
  end
end

class Lit < Outer::Base
  def get
    NS
  end
end

LibC.exit(Lit.new.get)"

POSITIVE=(ivar_default_from_parent method_from_parent included_module generic_parent ancestor_before_namespace)
NEGATIVE=(parent_namespace_rejected)

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
    printf 'FAIL %s (run): exit %s, expected 42\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]] && grep -q "undefined constant" "$log"; then
    printf 'PASS %s (rejected)\n' "$name"
  else
    printf 'FAIL %s: expected an undefined constant error\n' "$name"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d inherited constant case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Inherited constant cases passed\n'
