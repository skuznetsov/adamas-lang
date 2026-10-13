#!/usr/bin/env bash
# Macro argument transfer must preserve source payload across parser arenas.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-argument-reparse.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

cat >"$WORK_DIR/record_macro.cr" <<'CR'
macro record(__name name, *properties, **kwargs)
  struct {{name.id}}
    getter value : Int32

    def initialize(@value : Int32)
    end
  end
end
CR

cat >"$WORK_DIR/constant_macro.cr" <<'CR'
macro inspect_arg(name)
  {{name.stringify}}
end
CR

cat >"$WORK_DIR/string_macro.cr" <<'CR'
macro record(name)
  struct Handler
    getter value : Int32

    def initialize(@value : Int32)
    end
  end
end
CR

cat >"$WORK_DIR/constant_identifier.cr" <<'CR'
require "./constant_macro"

lib LibC
  fun exit(status : Int32) : NoReturn
end

value = inspect_arg(Foo)
LibC.exit(0)
CR

cat >"$WORK_DIR/typed_record.cr" <<'CR'
require "./record_macro"

lib LibC
  fun exit(status : Int32) : NoReturn
end

class Owner
  record Handler, value : Int32
end

recorded = Owner::Handler.new(73)
LibC.exit(recorded.value == 73 ? 0 : 1)
CR

cat >"$WORK_DIR/string_control.cr" <<'CR'
require "./string_macro"

lib LibC
  fun exit(status : Int32) : NoReturn
end

class Owner
  record "control"
end

recorded = Owner::Handler.new(41)
LibC.exit(recorded.value == 41 ? 0 : 1)
CR

run_case() {
  local name="$1"
  local source="$2"
  local log="$WORK_DIR/$name.compile.log"
  local output="$WORK_DIR/$name"
  local run_log="$WORK_DIR/$name.run.log"

  if ! DEBUG_MACRO_ARGS=1 DEBUG_MACRO_RESULT=1 DEBUG_MACRO_REPARSE=1 DEBUG_MACRO_OUTPUT=1 \
      "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 45 2048 \
      "$source" --no-prelude -o "$output" >"$log" 2>&1; then
    echo "compile failed: $name" >&2
    tail -80 "$log" >&2
    exit 1
  fi

  if ! "$ROOT_DIR/scripts/run_safe.sh" "$output" 5 512 >"$run_log" 2>&1; then
    echo "runtime failed: $name" >&2
    cat "$run_log" >&2
    exit 1
  fi
}

run_case constant_identifier "$WORK_DIR/constant_identifier.cr"
run_case typed_record "$WORK_DIR/typed_record.cr"
run_case string_control "$WORK_DIR/string_control.cr"

constant_log="$WORK_DIR/constant_identifier.compile.log"
typed_log="$WORK_DIR/typed_record.compile.log"
string_log="$WORK_DIR/string_control.compile.log"

# The diagnostic class name may remain Frontend::Node in a generated stage2;
# the stable contract is a valid reparse and preserved source payload.
rg -q 'MACRO_REPARSE.*arg0 .*reparsed_id=[0-9]+' "$constant_log" || {
  echo "regression: constant identifier did not transfer to the target arena" >&2
  exit 1
}
rg -q 'MACRO_OUTPUT.*Foo' "$constant_log" || {
  echo "regression: constant identifier payload was not preserved" >&2
  exit 1
}
rg -q 'MACRO_RESULT.*valid=true' "$constant_log" || {
  echo "regression: constant identifier macro expansion was rejected" >&2
  exit 1
}

rg -q 'MACRO_ARGS.*raw0=.*Handler' "$typed_log" || {
  echo "regression: identifier macro argument payload was lost" >&2
  exit 1
}
rg -q 'MACRO_ARGS.*raw1=.*value : Int32' "$typed_log" || {
  echo "regression: typed declaration source payload was lost" >&2
  exit 1
}
rg -q 'MACRO_REPARSE.*arg0 .*reparsed_id=[0-9]+' "$typed_log" || {
  echo "regression: identifier argument was not transferred across arenas" >&2
  exit 1
}
rg -q 'MACRO_REPARSE.*arg1 .*reparsed_id=[0-9]+' "$typed_log" || {
  echo "regression: typed declaration was not transferred across arenas" >&2
  exit 1
}
rg -q 'MACRO_REPARSE.*source_tdecl name=value' "$typed_log" || {
  echo "regression: typed declaration did not reach source-node inspection" >&2
  exit 1
}
rg -q 'MACRO_RESULT.*valid=true' "$typed_log" || {
  echo "regression: typed record macro expansion was rejected" >&2
  exit 1
}
rg -q 'MACRO_OUTPUT.*getter value : Int32' "$typed_log" || {
  echo "regression: typed record getter was not generated" >&2
  exit 1
}

arena_line="$(rg -m1 'MACRO_REPARSE.*source_arena=[0-9]+ target_arena=[0-9]+' "$typed_log")" || {
  echo "regression: cross-arena reparse was not observed" >&2
  exit 1
}
source_arena="$(sed -E 's/.*source_arena=([0-9]+).*/\1/' <<<"$arena_line")"
target_arena="$(sed -E 's/.*target_arena=([0-9]+).*/\1/' <<<"$arena_line")"
if [[ "$source_arena" == "$arena_line" || "$target_arena" == "$arena_line" || "$source_arena" == "$target_arena" ]]; then
  echo "regression: macro argument reparse did not use distinct arenas" >&2
  exit 1
fi

rg -q 'MACRO_RESULT.*valid=true' "$string_log" || {
  echo "regression: string control macro expansion was rejected" >&2
  exit 1
}
rg -q 'MACRO_OUTPUT.*getter value : Int32' "$string_log" || {
  echo "regression: string control getter was not generated" >&2
  exit 1
}

echo "macro_argument_reparse_np_ok"
