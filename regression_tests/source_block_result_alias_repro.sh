#!/usr/bin/env bash
# Alias expansion must preserve structural callback result restrictions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-4096}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
ONLY_CASES="${ONLY_CASES:-all}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/source-block-result-alias.XXXXXX")"

cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache-*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ "$ORIGINAL_ONLY" != 0 && "$ORIGINAL_ONLY" != 1 ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -f "$CRYSTAL_STDLIB/empty.cr" ]]; then
  echo "ERROR: safe runner, original Crystal, or stock Crystal stdlib is unavailable" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != 1 && ! -x "$ADAMAS_BIN" ]]; then
  echo "ERROR: candidate compiler is unavailable; set ADAMAS_BIN or ORIGINAL_ONLY=1" >&2
  exit 2
fi

ALL_CASES=(own_alias inherited_alias chained_alias input_named_default lexical_leaf nullable_alias direct_control wrong_field_type wrong_field_key unknown_leaf)
if [[ "$ONLY_CASES" == all ]]; then
  SELECTED_CASES=("${ALL_CASES[@]}")
else
  read -r -a SELECTED_CASES <<<"${ONLY_CASES//,/ }"
  [[ "${#SELECTED_CASES[@]}" != 0 ]] || { echo "ERROR: empty ONLY_CASES" >&2; exit 2; }
  for selected in "${SELECTED_CASES[@]}"; do
    found=0
    for available in "${ALL_CASES[@]}"; do
      [[ "$selected" == "$available" ]] && found=1
    done
    [[ "$found" == 1 ]] || { printf 'ERROR: unknown case %s\n' "$selected" >&2; exit 2; }
  done
fi

write_source() {
  local name="$1" path="$WORK_DIR/$1.cr" restriction expression
  cat >"$path" <<'CRYSTAL'
@[Link("c")]
lib SourceBlockAliasOutput
  fun putchar(value : Int32) : Int32
end

class SourceBlockAliasFactory(K, V)
  def self.new(initial_capacity = nil, &block : -> V)
    yield
  end

  def self.with_key(key : K, initial_capacity = nil, &block : K -> V)
    yield key
  end
end

module AliasScope
  class BaseUser
    alias Permissions = NamedTuple(config: Int32, read: Int32, write: Int32)
  end

  class User < BaseUser
    alias OwnPermissions = NamedTuple(config: Int32, read: Int32, write: Int32)
    alias Again = OwnPermissions
    alias MaybePermissions = OwnPermissions | Nil
  end
end
CRYSTAL
  restriction=AliasScope::User::OwnPermissions
  expression='{config: 65, read: 66, write: 67}'
  case "$name" in
    own_alias) ;;
    inherited_alias) restriction=AliasScope::User::Permissions ;;
    chained_alias) restriction=AliasScope::User::Again ;;
    input_named_default)
      cat >>"$path" <<'CRYSTAL'
value = SourceBlockAliasFactory(Int32, AliasScope::User::Permissions).with_key(65, initial_capacity: 4) do |key|
  {config: key, read: 66, write: 67}
end
SourceBlockAliasOutput.putchar(value[:config])
CRYSTAL
      return
      ;;
    lexical_leaf)
      cat >>"$path" <<'CRYSTAL'
module DeclarationScope
  class Item
    def marker : Int32
      65
    end
  end
  alias Fields = NamedTuple(item: Item)
end
module CallerScope
  class Item
  end
  def self.run
    value = SourceBlockAliasFactory(String, DeclarationScope::Fields).new { {item: DeclarationScope::Item.new} }
    SourceBlockAliasOutput.putchar(value[:item].marker)
  end
end
CallerScope.run
CRYSTAL
      return
      ;;
    nullable_alias) restriction=AliasScope::User::MaybePermissions ;;
    direct_control) restriction='NamedTuple(config: Int32, read: Int32, write: Int32)' ;;
    wrong_field_type) expression='{config: 65_i64, read: 66, write: 67}' ;;
    wrong_field_key) expression='{config: 65, read: 66, other: 67}' ;;
    unknown_leaf)
      cat >>"$path" <<'CRYSTAL'
module AliasScope
  alias UnknownFields = NamedTuple(config: MissingField)
end
SourceBlockAliasFactory(String, AliasScope::UnknownFields).new { {config: 65} }
CRYSTAL
      return
      ;;
  esac
  printf 'value = SourceBlockAliasFactory(String, %s).new { %s }\n' "$restriction" "$expression" >>"$path"
  if [[ "$name" == nullable_alias ]]; then
    cat >>"$path" <<'CRYSTAL'
if value
  SourceBlockAliasOutput.putchar(value[:config])
else
  SourceBlockAliasOutput.putchar(88)
end
CRYSTAL
  else
    printf 'SourceBlockAliasOutput.putchar(value[:config])\n' >>"$path"
  fi
}

compile_one() {
  local stage="$1" name="$2" binary="$WORK_DIR/$1-$2.bin"
  local log="$WORK_DIR/$1-$2.build.log" cache="$WORK_DIR/cache-$1-$2" status=0
  local -a mode_env
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      build --prelude=empty --no-debug "$WORK_DIR/$name.cr" -o "$binary" "--link-flags=$LINK_FLAGS" >"$log" 2>&1 || status=$?
  else
    if [[ "$stage" == candidate-eager ]]; then
      mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    else
      mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    fi
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" \
      "${mode_env[@]}" "$SAFE_RUNNER" "$ADAMAS_BIN" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$WORK_DIR/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1 || status=$?
  fi
  printf '%s\n' "$status" >"$WORK_DIR/$stage-$name.build.status"
}

check_case() {
  local stage="$1" name="$2" status=0 stdout="$WORK_DIR/$1-$2.stdout"
  local log="$WORK_DIR/$1-$2.build.log" binary="$WORK_DIR/$1-$2.bin"
  compile_one "$stage" "$name"
  status="$(cat "$WORK_DIR/$stage-$name.build.status")"
  if [[ "$name" == wrong_* || "$name" == unknown_leaf ]]; then
    if [[ "$status" != 1 ]] || ! rg -q '^\[EXIT: 1\]( |$)' "$log" || \
       ! rg -qi 'block.*return|return.*block|block result|MissingField|undefined constant|must be' "$log" || \
       rg -qi 'syntax error|parser errors|internal compiler error|unhandled exception|timed out|resource limit' "$log"; then
      cat "$log" >&2
      printf 'FAIL %s %s: expected source-level rejection (exit 1)\n' "$stage" "$name" >&2
      return 1
    fi
    printf 'PASS %s %s rejected\n' "$stage" "$name"
    return
  fi
  if [[ "$status" != 0 ]] || ! rg -q '^\[EXIT: 0\]( |$)' "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: compile did not exit zero\n' "$stage" "$name" >&2
    return 1
  fi
  status=0
  log="$WORK_DIR/$stage-$name.run.log"
  RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.resources.json" \
    "$SAFE_RUNNER" "$binary" 10 512 >"$stdout" 2>"$log" || status=$?
  printf 'A' >"$WORK_DIR/$name.expected"
  if [[ "$status" != 0 ]] || ! rg -q '^\[EXIT: 0\]( |$)' "$log" || \
     ! diff -u "$WORK_DIR/$name.expected" "$stdout"; then
    cat "$log" "$stdout" >&2
    printf 'FAIL %s %s: native output differed\n' "$stage" "$name" >&2
    return 1
  fi
  if [[ "$stage" != original ]] && ! diff -u "$WORK_DIR/original-$name.stdout" "$stdout"; then
    return 1
  fi
  printf 'PASS %s %s output=A\n' "$stage" "$name"
}

for name in "${SELECTED_CASES[@]}"; do
  write_source "$name"
  check_case original "$name"
  if [[ "$ORIGINAL_ONLY" != 1 ]]; then
    check_case candidate-lazy "$name"
    check_case candidate-eager "$name"
  fi
done
