#!/usr/bin/env bash
# Continuity guard for concrete and union generic materialization.
#
# Default mode compiles the reducer to HIR and checks two lawful, distinct
# corridors:
#   * concrete AstArena insertion selects <<$AstArena -> push$AstArena;
#   * explicit `.as(ArenaLike)` and an ArenaLike parameter select the union
#     << / push specialization.
# Every selected helper must keep receiver+value and have a real HIR body.
# This guard does not require concrete and union corridors to share identity.
#
# Artifact-classifier mode:
#   ADAMAS_UNION_MATERIALIZATION_LLVM=/path/to/full-stage.ll ./this-script
# skips compilation.  It records the exact known full-G9 zero-argument call
# plus unreachable definition as MEASURED_RED; other malformed mixed shapes
# fail, and a green artifact needs two-argument concrete and union push edges.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TIMEOUT_SEC="${UNION_STATIC_GENERIC_TIMEOUT_SEC:-60}"
MEM_MB="${UNION_STATIC_GENERIC_MEM_MB:-2048}"
FULL_LL="${ADAMAS_UNION_MATERIALIZATION_LLVM:-}"
KEEP_TMP="${KEEP_TMP:-0}"

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [compiler]" >&2
  exit 2
fi

count_fixed() {
  local file="$1"
  local needle="$2"
  awk -v needle="$needle" 'index($0, needle) { count += 1 } END { print count + 0 }' "$file"
}

function_block() {
  local file="$1"
  local prefix="$2"
  awk -v prefix="$prefix" '
    !inside && index($0, prefix) == 1 { inside = 1 }
    inside { print }
    inside && /^}$/ { exit }
  ' "$file"
}

count_in_text() {
  local text_value="$1"
  local needle="$2"
  printf '%s\n' "$text_value" | awk -v needle="$needle" 'index($0, needle) { count += 1 } END { print count + 0 }'
}

llvm_two_arg_call_count() {
  local file="$1"
  local symbol="$2"
  awk -v prefix="call ptr @$symbol(" '
    index($0, prefix) {
      rest = substr($0, index($0, prefix) + length(prefix))
      close_pos = index(rest, ")")
      args = substr(rest, 1, close_pos - 1)
      if (args ~ /^ptr [^,()]+, ptr [^,()]+$/) count += 1
    }
    END { print count + 0 }
  ' "$file"
}

classify_llvm() {
  local file="$1"
  local static_target='Array$LAdamas$CCCompiler$CCFrontend$CCAstArena$_$OR$_Adamas$CCCompiler$CCFrontend$CCPageArena$_$OR$_Adamas$CCCompiler$CCFrontend$CCVirtualArena$R$Hpush$$Adamas$CCCompiler$CCFrontend$CCAstArena'
  local union_target='Array$LAdamas$CCCompiler$CCFrontend$CCAstArena$_$OR$_Adamas$CCCompiler$CCFrontend$CCPageArena$_$OR$_Adamas$CCCompiler$CCFrontend$CCVirtualArena$R$Hpush$$Adamas$CCCompiler$CCFrontend$CCAstArena$_$OR$_Adamas$CCCompiler$CCFrontend$CCPageArena$_$OR$_Adamas$CCCompiler$CCFrontend$CCVirtualArena'

  if [[ ! -s "$file" ]]; then
    echo "ERROR: LLVM artifact is missing or empty: $file" >&2
    return 2
  fi

  local zero_calls zero_defs zero_body zero_returns zero_unreachable
  zero_calls="$(count_fixed "$file" "call ptr @$static_target()")"
  zero_defs="$(count_fixed "$file" "define ptr @$static_target()")"
  zero_body="$(function_block "$file" "define ptr @$static_target()")"
  zero_returns="$(count_in_text "$zero_body" '  ret ')"
  zero_unreachable="$(count_in_text "$zero_body" '  unreachable')"

  echo "llvm=$file"
  echo "zero_arg_calls=$zero_calls"
  echo "zero_arg_definitions=$zero_defs"
  echo "zero_arg_body_returns=$zero_returns"
  echo "zero_arg_body_unreachable=$zero_unreachable"

  if [[ "$zero_calls" -ge 1 && "$zero_defs" == "1" && \
        "$zero_returns" == "0" && "$zero_unreachable" -ge 1 ]]; then
    echo "MEASURED_RED: Array(ArenaLike)#push(AstArena) lost receiver+value and materialized an unreachable zero-argument definition" >&2
    return 0
  fi

  if [[ "$zero_calls" != "0" || "$zero_defs" != "0" ]]; then
    echo "FAIL: zero-argument Array(ArenaLike)#push(AstArena) shape is present but does not match the classified G9 stub" >&2
    return 1
  fi

  local static_calls union_calls static_defs union_defs
  static_calls="$(llvm_two_arg_call_count "$file" "$static_target")"
  union_calls="$(llvm_two_arg_call_count "$file" "$union_target")"
  static_defs="$(count_fixed "$file" "define ptr @$static_target(ptr %self, ptr %value) {")"
  union_defs="$(count_fixed "$file" "define ptr @$union_target(ptr %self, ptr %value) {")"

  echo "static_two_arg_calls=$static_calls"
  echo "static_two_arg_definitions=$static_defs"
  echo "union_two_arg_calls=$union_calls"
  echo "union_two_arg_definitions=$union_defs"

  if [[ "$static_calls" -lt 1 || "$union_calls" -lt 1 || \
        "$static_defs" != "1" || "$union_defs" != "1" ]]; then
    echo "FAIL: relevant union-Array push calls/definitions are not consistently two-argument" >&2
    return 1
  fi

  echo "union_static_generic_materialization_llvm_ok"
}

if [[ -n "$FULL_LL" ]]; then
  classify_llvm "$FULL_LL"
  exit $?
fi

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found or not executable: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union_static_generic_materialization.XXXXXX")"
cleanup() {
  if [[ "$KEEP_TMP" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$ROOT_DIR/regression_tests/union_static_generic_materialization_guard.cr"
OUT="$TMP_DIR/probe"
HIR="$OUT.hir"
LOG="$TMP_DIR/compiler.log"

if [[ ! -s "$SRC" ]]; then
  echo "ERROR: missing reducer source: $SRC" >&2
  exit 2
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
  "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1
compile_status=$?
set -e
if [[ $compile_status -ne 0 || ! -s "$HIR" ]]; then
  echo "ERROR: HIR emission failed (status=$compile_status)" >&2
  tail -120 "$LOG" >&2 || true
  exit 2
fi

hir_type_id() {
  local description="$1"
  awk -v description="$description" '
    index($0, description) {
      value = $1
      sub(/^type\./, "", value)
      print value
    }
  ' "$HIR"
}

AST_ID="$(hir_type_id ' = Class AstArena')"
UNION_ID="$(hir_type_id ' = Union AstArena | PageArena | VirtualArena')"
ARRAY_ID="$(hir_type_id ' = Array Array(AstArena | PageArena | VirtualArena)(')"
if [[ -z "$AST_ID" || -z "$UNION_ID" || -z "$ARRAY_ID" ]]; then
  echo "ERROR: reducer HIR type ids are incomplete" >&2
  exit 2
fi

APPEND_STATIC='append_static$Array(AstArena | PageArena | VirtualArena)_AstArena'
APPEND_EXPLICIT='append_explicit$Array(AstArena | PageArena | VirtualArena)_AstArena'
APPEND_UNION='append_union$Array(AstArena | PageArena | VirtualArena)_AstArena | PageArena | VirtualArena'
SHL_STATIC='Array(AstArena | PageArena | VirtualArena)#<<$AstArena'
SHL_UNION='Array(AstArena | PageArena | VirtualArena)#<<$AstArena | PageArena | VirtualArena'
PUSH_STATIC='Array(AstArena | PageArena | VirtualArena)#push$AstArena'
PUSH_UNION='Array(AstArena | PageArena | VirtualArena)#push$AstArena | PageArena | VirtualArena'

failures=0
fail_check() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

require_signature() {
  local signature="$1"
  local label="$2"
  local count
  count="$(awk -v signature="$signature" '$0 == signature { count += 1 } END { print count + 0 }' "$HIR")"
  if [[ "$count" != "1" ]]; then
    fail_check "$label signature count=$count"
  fi
}

require_real_body() {
  local symbol="$1"
  local label="$2"
  local body blocks returns
  body="$(function_block "$HIR" "func @$symbol(")"
  blocks="$(count_in_text "$body" '  block.0')"
  returns="$(count_in_text "$body" '    return')"
  if [[ "$blocks" -lt 1 || "$returns" -lt 1 ]]; then
    fail_check "$label is missing a real HIR body"
  fi
}

require_member_call() {
  local owner_symbol="$1"
  local target_symbol="$2"
  local label="$3"
  local body stats valid selected
  body="$(function_block "$HIR" "func @$owner_symbol(")"
  stats="$(printf '%s\n' "$body" | awk -v target=".$target_symbol(" '
    / = call / {
      position = index($0, target)
      if (position > 0) {
        selected += 1
        rest = substr($0, position + length(target))
        close_pos = index(rest, ")")
        args = substr(rest, 1, close_pos - 1)
        if (index($0, "call %") > 0 && args ~ /^%[0-9]+$/) valid += 1
      }
    }
    END { print valid + 0, selected + 0 }
  ')"
  read -r valid selected <<<"$stats"
  if [[ "$valid" != "1" || "$selected" != "1" ]]; then
    fail_check "$label must select exactly one receiver+value call (valid=$valid selected=$selected)"
  fi
}

# Append boundaries and selected method bodies must agree on their exact
# receiver/value/return types.  In particular, an explicit cast changes the
# value corridor, not the Array return type.
require_signature "func @$APPEND_STATIC(%0: $ARRAY_ID, %1: $AST_ID) -> $ARRAY_ID {" "concrete append"
require_signature "func @$APPEND_EXPLICIT(%0: $ARRAY_ID, %1: $AST_ID) -> $ARRAY_ID {" "explicit-cast append"
require_signature "func @$APPEND_UNION(%0: $ARRAY_ID, %1: $UNION_ID) -> $ARRAY_ID {" "union-parameter append"
require_signature "func @$SHL_STATIC(%0: $ARRAY_ID, %1: $AST_ID) -> $ARRAY_ID {" "concrete <<"
require_signature "func @$SHL_UNION(%0: $ARRAY_ID, %1: $UNION_ID) -> $ARRAY_ID {" "union <<"
require_signature "func @$PUSH_STATIC(%0: $ARRAY_ID, %1: $AST_ID) -> $ARRAY_ID {" "concrete push"
require_signature "func @$PUSH_UNION(%0: $ARRAY_ID, %1: $UNION_ID) -> $ARRAY_ID {" "union push"
for body_symbol in "$APPEND_STATIC" "$APPEND_EXPLICIT" "$APPEND_UNION" "$SHL_STATIC" "$SHL_UNION" "$PUSH_STATIC" "$PUSH_UNION"; do
  require_real_body "$body_symbol" "$body_symbol"
done
require_member_call "$SHL_STATIC" "$PUSH_STATIC" "concrete << -> push"
require_member_call "$SHL_UNION" "$PUSH_UNION" "union << -> push"

# Source corridors select the intended, distinct `<<` targets.  The explicit
# cast must survive as a HIR cast; the true union parameter needs no local cast.
require_member_call "$APPEND_STATIC" "$SHL_STATIC" "concrete append -> <<"
require_member_call "$APPEND_EXPLICIT" "$SHL_UNION" "explicit cast append -> <<"
require_member_call "$APPEND_UNION" "$SHL_UNION" "union parameter append -> <<"
EXPLICIT_BODY="$(function_block "$HIR" "func @$APPEND_EXPLICIT(")"
STATIC_BODY="$(function_block "$HIR" "func @$APPEND_STATIC(")"
UNION_BODY="$(function_block "$HIR" "func @$APPEND_UNION(")"
if [[ "$(count_in_text "$STATIC_BODY" 'union_wrap')" != "0" || \
      "$(count_in_text "$STATIC_BODY" ' = cast ')" != "0" ]]; then
  fail_check 'concrete AstArena was converted before the concrete <<$AstArena target'
fi
if [[ "$(count_in_text "$EXPLICIT_BODY" " as $UNION_ID")" -lt 1 ]]; then
  fail_check "explicit .as(ArenaLike) did not survive as a union cast"
fi
if [[ "$(count_in_text "$UNION_BODY" ' = cast ')" != "0" ]]; then
  fail_check "true union parameter was spuriously recast inside append_union"
fi

echo "compiler=$COMPILER"
echo "hir=$HIR"
echo "hir_contract_failures=$failures"
if [[ $failures -ne 0 ]]; then
  echo "union-static generic materialization HIR continuity is RED" >&2
  awk -v prefix="func @$APPEND_EXPLICIT(" 'index($0, prefix) == 1 { print "actual_explicit_signature=" $0 }' "$HIR" >&2
  printf '%s\n' "$STATIC_BODY" | awk '/union_wrap|#<<\$AstArena/ { print "concrete_path=" $0 }' >&2
  exit 1
fi

echo "union_static_generic_materialization_hir_ok"
