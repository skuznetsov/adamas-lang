#!/usr/bin/env bash
# Module registration macros must reflect the declaration owner.
# Native controls cover sibling/nested modules, class context and TLS properties.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-macro-owner-reflection.XXXXXX")"

cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 || "${KEEP_TMP:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL" ]]; then
  echo "ERROR: candidate and original compilers must be executable" >&2
  exit 2
fi

cat >"$WORK_DIR/reflection.cr" <<'CRYSTAL'
class Object
  macro declare_owner_label
    def self.owner_label : String
      {{@type.name.stringify}}
    end
  end
end

module MacroOwnerFirst
  declare_owner_label
end

module MacroOwnerOuter
  module Inner
    declare_owner_label
  end
end

class MacroOwnerClass
  declare_owner_label
end

module MacroOwnerLast
  declare_owner_label
end

puts MacroOwnerFirst.owner_label
puts MacroOwnerOuter::Inner.owner_label
puts MacroOwnerClass.owner_label
puts MacroOwnerLast.owner_label
CRYSTAL
cat >"$WORK_DIR/thread_cache.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end
module OwnerReflectionCache
  thread_local(cached_value : Int32) { 65 }
end
module OwnerReflectionOuter
  module Inner
    thread_local(cached_value : Int32) { 66 }
  end
end
LibC.putchar(OwnerReflectionCache.cached_value)
LibC.putchar(OwnerReflectionOuter::Inner.cached_value)
LibC.putchar(Thread.current.__tls_OwnerReflectionCache__cached_value.not_nil!)
LibC.putchar(Thread.current.__tls_OwnerReflectionOuter__Inner__cached_value.not_nil!)
LibC.putchar(10)
CRYSTAL
cat >"$WORK_DIR/kind.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end
class Object
  macro declare_owner_kind
    def self.module_flag : Bool
      {{@type.module?}}
    end
    def self.class_flag : Bool
      {{@type.class?}}
    end
    def self.struct_flag : Bool
      {{@type.struct?}}
    end
    def self.called_module_flag : Bool
      {{@type.module?()}}
    end
  end
end
module OwnerKindModule
  declare_owner_kind
end
class OwnerKindClass
  declare_owner_kind
end
struct OwnerKindStruct
  declare_owner_kind
end
LibC.putchar(OwnerKindModule.module_flag ? 49 : 48)
LibC.putchar(OwnerKindModule.class_flag ? 49 : 48)
LibC.putchar(OwnerKindModule.struct_flag ? 49 : 48)
LibC.putchar(OwnerKindModule.called_module_flag ? 49 : 48)
LibC.putchar(OwnerKindClass.module_flag ? 49 : 48)
LibC.putchar(OwnerKindClass.class_flag ? 49 : 48)
LibC.putchar(OwnerKindClass.struct_flag ? 49 : 48)
LibC.putchar(OwnerKindClass.called_module_flag ? 49 : 48)
LibC.putchar(OwnerKindStruct.module_flag ? 49 : 48)
LibC.putchar(OwnerKindStruct.class_flag ? 49 : 48)
LibC.putchar(OwnerKindStruct.struct_flag ? 49 : 48)
LibC.putchar(OwnerKindStruct.called_module_flag ? 49 : 48)
LibC.putchar(10)
CRYSTAL
cat >"$WORK_DIR/reflection.expected" <<'EXPECTED'
MacroOwnerFirst
MacroOwnerOuter::Inner
MacroOwnerClass
MacroOwnerLast
EXPECTED
printf 'ABAB\n' >"$WORK_DIR/thread_cache.expected"

printf '100101000010\n' >"$WORK_DIR/kind.expected"

for fixture in reflection thread_cache kind; do
  for stage in original candidate; do
    compiler="$COMPILER"
    args=("$WORK_DIR/$fixture.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/$fixture.$stage")
    if [[ "$stage" == "original" ]]; then
      compiler="$ORIGINAL_CRYSTAL"
      args=(build "$WORK_DIR/$fixture.cr" -o "$WORK_DIR/$fixture.$stage" --no-debug --error-trace --link-flags=-fuse-ld=/usr/bin/ld)
    fi
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/$fixture.$stage.cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$fixture.$stage.build.resources" \
        "$ROOT_DIR/scripts/run_safe.sh" "$compiler" 180 8192 "${args[@]}" \
        >"$WORK_DIR/$fixture.$stage.build.log" 2>&1; then
      echo "FAIL[$stage/$fixture]: compilation failed" >&2
      tail -20 "$WORK_DIR/$fixture.$stage.build.log" >&2
      exit 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$fixture.$stage.run.resources" \
        "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$fixture.$stage" 10 512 \
        >"$WORK_DIR/$fixture.$stage.actual" 2>"$WORK_DIR/$fixture.$stage.run.log"; then
      echo "FAIL[$stage/$fixture]: runtime failed" >&2
      tail -20 "$WORK_DIR/$fixture.$stage.run.log" >&2
      exit 1
    fi
    if ! diff -u "$WORK_DIR/$fixture.expected" "$WORK_DIR/$fixture.$stage.actual" >&2; then
      echo "FAIL[$stage/$fixture]: declaration owner output differs" >&2
      exit 1
    fi
    echo "PASS[$stage/$fixture]: declaration owner and native context agree"
  done
done
