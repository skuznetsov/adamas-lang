#!/usr/bin/env bash
# Compare Crystal and Adamas on nullable Proc inference through calls and
# control-flow joins. The fixtures are embedded so this regression is portable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
if [[ -n "${REPO_ROOT:-}" ]]; then
  ROOT_DIR="$(cd "${REPO_ROOT}" && pwd -P)"
else
  ROOT_DIR="$SCRIPT_DIR"
  while [[ "$ROOT_DIR" != "/" && ! -x "$ROOT_DIR/scripts/run_safe.sh" ]]; do
    ROOT_DIR="$(dirname "$ROOT_DIR")"
  done
  if [[ ! -x "$ROOT_DIR/scripts/run_safe.sh" ]]; then
    echo "ERROR: set REPO_ROOT to an Adamas checkout with scripts/run_safe.sh" >&2
    exit 2
  fi
fi

SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
if [[ -n "${1:-}" ]]; then
  COMPILER="$1"
elif [[ -n "${ADAMAS_BIN:-}" ]]; then
  COMPILER="$ADAMAS_BIN"
else
  COMPILER="$ROOT_DIR/bin/adamas"
fi

if [[ -n "${ORIGINAL_CRYSTAL_BIN:-}" ]]; then
  ORIGINAL_CRYSTAL="$ORIGINAL_CRYSTAL_BIN"
elif [[ -n "${ORIGINAL_CRYSTAL:-}" ]]; then
  ORIGINAL_CRYSTAL="$ORIGINAL_CRYSTAL"
else
  ORIGINAL_CRYSTAL="$(command -v crystal || true)"
fi

if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  BASE_CRYSTAL_PATH="$CRYSTAL_PATH"
else
  if [[ -n "${CRYSTAL_STDLIB:-}" ]]; then
    CRYSTAL_STDLIB="$CRYSTAL_STDLIB"
  else
    CRYSTAL_STDLIB="$ROOT_DIR/../crystal/src"
  fi
  if [[ ! -d "$CRYSTAL_STDLIB" ]]; then
    echo "ERROR: set CRYSTAL_PATH or CRYSTAL_STDLIB to the immutable Crystal stdlib" >&2
    exit 2
  fi
  BASE_CRYSTAL_PATH="$CRYSTAL_STDLIB"
fi

PRELUDE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nullable-proc-prelude.XXXXXX")"
cat > "$PRELUDE_DIR/empty_prelude.cr" <<'CR'
lib LibCrystalMain
  fun __crystal_main(argc : Int32, argv : UInt8**)
end

fun main(argc : Int32, argv : UInt8**) : Int32
  LibCrystalMain.__crystal_main(argc, argv)
  0
end
CR
export CRYSTAL_PATH="$PRELUDE_DIR:$BASE_CRYSTAL_PATH"
LINK_FLAGS="${LINK_FLAGS:-${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}}"
export ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS"

for tool in "$SAFE_RUNNER" "$COMPILER" "$ORIGINAL_CRYSTAL"; do
  if [[ -z "$tool" || ! -x "$tool" ]]; then
    echo "ERROR: required executable is missing: $tool" >&2
    rm -rf "$PRELUDE_DIR"
    exit 2
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nullable-proc-branch.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR"/*.cache
  rm -rf "$PRELUDE_DIR"
  if [[ "$status" -ne 0 || "${KEEP_TMP:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

write_fixture() {
  local name="$1"
  local path="$WORK_DIR/$name.cr"
  case "$name" in
    nullable_box_type_transfer)
      cat > "$path" <<'CR'
lib ProbeC
  fun putchar(value : Int32) : Int32
end

class Box(T)
  def self.capture(value : T) : T
    value
  end
end

class BoxingCaller(T)
  def self.box_and_recover(value : Proc(Int32, Int32)?)
    Box.capture(value)
  end
end

def optional_callback(flag : Bool)
  if flag
    ->(value : Int32) { 42 }
  else
    nil
  end
end

first = BoxingCaller(Pointer(Void)).box_and_recover(optional_callback(true))
second = BoxingCaller(Pointer(Void)).box_and_recover(optional_callback(false))

ProbeC.putchar(first ? 84 : 70)
ProbeC.putchar(second ? 84 : 70)
ProbeC.putchar(10)
CR
      ;;
    nullable_box_unknown_call_arm)
      cat > "$path" <<'CR'
lib ProbeC
  fun putchar(value : Int32) : Int32
end

class Box(T)
  def self.capture(value : T) : T
    value
  end
end

def callback_source(flag : Bool)
  if flag
    ->(value : Int32) { 42 }
  else
    nil
  end
end

def callback_through_unknown_call(flag : Bool)
  if flag
    callback_source(true)
  else
    nil
  end
end

first = Box.capture(callback_through_unknown_call(true))
second = Box.capture(callback_through_unknown_call(false))
ProbeC.putchar(first ? 84 : 70)
ProbeC.putchar(second ? 84 : 70)
ProbeC.putchar(10)
CR
      ;;
    nullable_elsif_terminal_return)
      cat > "$path" <<'CR'
lib ProbeC
  fun putchar(value : Int32) : Int32
end

class Box(T)
  def self.capture(value : T) : T
    value
  end
end

def callback_with_elsif(first : Bool, second : Bool)
  if first
  elsif second
    ->(value : Int32) { 43 }
  else
    return nil
  end
end

first = Box.capture(callback_with_elsif(true, false))
second = Box.capture(callback_with_elsif(false, true))
third = Box.capture(callback_with_elsif(false, false))
ProbeC.putchar(first ? 84 : 70)
ProbeC.putchar(second ? 84 : 70)
ProbeC.putchar(third ? 84 : 70)
ProbeC.putchar(10)
CR
      ;;
    nullable_elsif_recursive_return)
      cat > "$path" <<'CR'
lib ProbeC
  fun putchar(value : Int32) : Int32
end

class Box(T)
  def self.capture(value : T) : T
    value
  end
end

def callback_with_elsif(first : Bool, second : Bool)
  if first
    callback_with_elsif(false, second)
  elsif second
    ->(value : Int32) { 43 }
  else
    return nil
  end
end

first = Box.capture(callback_with_elsif(true, false))
second = Box.capture(callback_with_elsif(false, true))
third = Box.capture(callback_with_elsif(false, false))
ProbeC.putchar(first ? 84 : 70)
ProbeC.putchar(second ? 84 : 70)
ProbeC.putchar(third ? 84 : 70)
ProbeC.putchar(10)
CR
      ;;
    nullable_elsif_unknown_recursive_arm)
      cat > "$path" <<'CR'
lib ProbeC
  fun putchar(value : Int32) : Int32
end

class Box(T)
  def self.capture(value : T) : T
    value
  end
end

def callback_source(flag : Bool)
  if flag
    ->(value : Int32) { 42 }
  else
    nil
  end
end

def callback_with_elsif(first : Bool, second : Bool)
  if first
    callback_with_elsif(false, false)
  elsif second
    ->(value : Int32) { 43 }
  else
    return nil
  end
end

first = Box.capture(callback_with_elsif(true, false))
second = Box.capture(callback_with_elsif(false, true))
third = Box.capture(callback_with_elsif(false, false))
ProbeC.putchar(first ? 84 : 70)
ProbeC.putchar(second ? 84 : 70)
ProbeC.putchar(third ? 84 : 70)
ProbeC.putchar(10)
CR
      ;;
    nullable_empty_elsif_else)
      cat > "$path" <<'CR'
lib ProbeC
  fun putchar(value : Int32) : Int32
end

def empty_elsif(first : Bool, second : Bool)
  if first
    ->(value : Int32) { 43 }
  elsif second
  else
    nil
  end
end

def empty_else(first : Bool, second : Bool)
  if first
    ->(value : Int32) { 43 }
  elsif second
    nil
  else
  end
end

ProbeC.putchar(empty_elsif(true, false) ? 84 : 70)
ProbeC.putchar(empty_elsif(false, true) ? 84 : 70)
ProbeC.putchar(empty_elsif(false, false) ? 84 : 70)
ProbeC.putchar(empty_else(true, false) ? 84 : 70)
ProbeC.putchar(empty_else(false, true) ? 84 : 70)
ProbeC.putchar(empty_else(false, false) ? 84 : 70)
ProbeC.putchar(10)
CR
      ;;
    nullable_missing_else_return_fallthrough)
      cat > "$path" <<'CR'
lib ProbeC
  fun putchar(value : Int32) : Int32
end

def callback_with_missing_else(flag : Bool)
  if flag
    ->(value : Int32) { 47 }
  end
end

def callback_return_then_fallthrough(flag : Bool)
  if flag
    return nil
  end
  ->(value : Int32) { 53 }
end

ProbeC.putchar(callback_with_missing_else(true) ? 84 : 70)
ProbeC.putchar(callback_with_missing_else(false) ? 84 : 70)
ProbeC.putchar(callback_return_then_fallthrough(true) ? 84 : 70)
ProbeC.putchar(callback_return_then_fallthrough(false) ? 84 : 70)
ProbeC.putchar(10)
CR
      ;;
    *)
      echo "ERROR: unknown fixture $name" >&2
      return 2
      ;;
  esac
  printf '%s\n' "$path"
}

assert_proc_nil_hir() {
  local hir="$1"
  local function_name="$2"
  local declaration type_id
  declaration="$(grep -F "func @$function_name$" "$hir" | head -n 1 || true)"
  if [[ -z "$declaration" ]]; then
    echo "FAIL[HIR]: missing function signature for $function_name" >&2
    return 1
  fi
  type_id="$(printf '%s\n' "$declaration" | sed -E 's/.* -> ([0-9]+) \{.*/\1/')"
  if [[ "$type_id" == "$declaration" || -z "$type_id" ]]; then
    echo "FAIL[HIR]: could not read return type for $function_name" >&2
    return 1
  fi
  if ! grep -Fq "  type.$type_id = Union Nil | Proc(Int32, Int32)" "$hir"; then
    echo "FAIL[HIR]: $function_name does not retain Union Nil | Proc(Int32, Int32)" >&2
    return 1
  fi
  if ! grep -F "call $function_name" "$hir" | grep -Fq ": $type_id"; then
    echo "FAIL[HIR]: callsite for $function_name does not preserve its Proc | Nil return type" >&2
    return 1
  fi
  echo "PASS[HIR]: $function_name and its callsite retain Union Nil | Proc(Int32, Int32)"
}

run_safe_build() {
  local compiler="$1"
  local mode="$2"
  local fixture="$3"
  local output="$4"
  local log="$5"
  local cache="$6"
  local resource="$7"
  if [[ "$mode" == original ]]; then
    env CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
      RUN_SAFE_RESOURCE_FILE="$resource" \
      "$SAFE_RUNNER" "$compiler" 180 12288 build "$fixture" \
        --prelude empty_prelude --no-debug --link-flags="$LINK_FLAGS" \
        -o "$output" >"$log" 2>&1
  else
    env CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
      RUN_SAFE_RESOURCE_FILE="$resource" \
      "$SAFE_RUNNER" "$compiler" 180 12288 "$fixture" \
        --no-prelude --no-ast-cache --no-llvm-cache --no-debug -o "$output" \
        >"$log" 2>&1
  fi
}

run_safe_program() {
  local binary="$1"
  local output="$2"
  local log="$3"
  local resource="$4"
  RUN_SAFE_PASSTHROUGH_STDIO=1 RUN_SAFE_RESOURCE_FILE="$resource" \
    "$SAFE_RUNNER" "$binary" 15 1024 >"$output" 2>"$log"
}

assert_output() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  printf '%b' "$expected" > "$WORK_DIR/expected.actual"
  if ! cmp -s "$actual" "$WORK_DIR/expected.actual"; then
    echo "FAIL[$label]: expected output $expected" >&2
    od -An -tx1c "$actual" >&2 || true
    return 1
  fi
}

case_names=(
  nullable_box_type_transfer
  nullable_box_unknown_call_arm
  nullable_elsif_terminal_return
  nullable_elsif_recursive_return
  nullable_elsif_unknown_recursive_arm
  nullable_empty_elsif_else
  nullable_missing_else_return_fallthrough
)
case_outputs=(
  'TF\n'
  'TF\n'
  'FTF\n'
  'FTF\n'
  'FTF\n'
  'TFFTFF\n'
  'TFFT\n'
)
case_functions=(
  optional_callback
  callback_through_unknown_call
  callback_with_elsif
  callback_with_elsif
  callback_with_elsif
  ''
  callback_with_missing_else
)

for index in 0 1 2 3 4 5 6; do
  name="${case_names[$index]}"
  expected="${case_outputs[$index]}"
  source="$(write_fixture "$name")"
  expected_sha=""
  case "$name" in
    nullable_box_type_transfer) expected_sha="df75df0054a29c4ee2ea134511dfb1c18a4a148e338b990202131e23495981df" ;;
    nullable_box_unknown_call_arm) expected_sha="5ec992ca9fc80f3bb2e6618b67281358f8d8dd0c3df576596b3fe29b7527a9fb" ;;
    nullable_elsif_terminal_return) expected_sha="f207a452156f0d26d7c4d8a8a13412fca781f97ce6c1ae5c257bec156c514255" ;;
    nullable_elsif_recursive_return) expected_sha="762983eacdf9154d589ca335363040370215a957e4a1806d46d5191664a8f572" ;;
    nullable_elsif_unknown_recursive_arm) expected_sha="cdec61d7dee65da61b5e4c13566843a1692bccd129d23486f934bbc709632807" ;;
    nullable_empty_elsif_else) expected_sha="ae35e59d8dfab8eecc7759c5e7f19ff049b3089a311efb503c259fab00073b22" ;;
    nullable_missing_else_return_fallthrough) expected_sha="56d7c7566a5240d26d992917ad140ac7b08f7e95b006ed4a0ada695a716b3b8b" ;;
  esac
  actual_sha="$(shasum -a 256 "$source" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "FAIL[fixture]: embedded source changed for $name ($actual_sha)" >&2
    exit 1
  fi

  # Run each Crystal oracle first so candidate outcomes are compared against
  # observed language behavior for the same exact source bytes.
  if ! run_safe_build "$ORIGINAL_CRYSTAL" original "$source" \
    "$WORK_DIR/$name.original" "$WORK_DIR/$name.original-build.log" \
    "$WORK_DIR/$name.original.cache" "$WORK_DIR/$name.original-build.resources"; then
    echo "FAIL[original:$name]: compilation failed" >&2
    tail -30 "$WORK_DIR/$name.original-build.log" >&2
    exit 1
  fi
  rm -rf "$WORK_DIR/$name.original.cache"
  if ! run_safe_program "$WORK_DIR/$name.original" \
    "$WORK_DIR/$name.original.actual" "$WORK_DIR/$name.original-run.log" \
    "$WORK_DIR/$name.original-run.resources"; then
    echo "FAIL[original:$name]: runtime failed" >&2
    tail -30 "$WORK_DIR/$name.original-run.log" >&2
    exit 1
  fi
  if ! assert_output "$WORK_DIR/$name.original.actual" "$expected" "original:$name"; then
    exit 1
  fi
  echo "PASS[original:$name]: $(printf '%b' "$expected" | tr -d '\n')"

  if ! run_safe_build "$COMPILER" candidate "$source" \
    "$WORK_DIR/$name.candidate" "$WORK_DIR/$name.candidate-build.log" \
    "$WORK_DIR/$name.candidate.cache" "$WORK_DIR/$name.candidate-build.resources"; then
    echo "FAIL[candidate:$name]: compilation failed" >&2
    tail -30 "$WORK_DIR/$name.candidate-build.log" >&2
    exit 1
  fi
  rm -rf "$WORK_DIR/$name.candidate.cache"
  if ! run_safe_program "$WORK_DIR/$name.candidate" \
    "$WORK_DIR/$name.candidate.actual" "$WORK_DIR/$name.candidate-run.log" \
    "$WORK_DIR/$name.candidate-run.resources"; then
    echo "FAIL[candidate:$name]: runtime failed" >&2
    tail -30 "$WORK_DIR/$name.candidate-run.log" >&2
    exit 1
  fi
  if ! assert_output "$WORK_DIR/$name.candidate.actual" "$expected" "candidate:$name"; then
    exit 1
  fi
  echo "PASS[candidate:$name]: $(printf '%b' "$expected" | tr -d '\n')"

  function_name="${case_functions[$index]}"
  if [[ -n "$function_name" ]]; then
    hir_base="$WORK_DIR/$name.candidate-hir"
    if ! env CRYSTAL_CACHE_DIR="$WORK_DIR/$name.hir.cache" ADAMAS_LLVM_CACHE=0 \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$name.hir.resources" \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$source" --no-prelude \
        --no-ast-cache --no-llvm-cache --no-debug --emit hir --no-link \
        -o "$hir_base" >"$WORK_DIR/$name.hir.log" 2>&1; then
      echo "FAIL[HIR:$name]: emission failed" >&2
      tail -30 "$WORK_DIR/$name.hir.log" >&2
      exit 1
    fi
    rm -rf "$WORK_DIR/$name.hir.cache"
    assert_proc_nil_hir "$hir_base.hir" "$function_name"
  fi
done

echo "PASS[nullable-proc-branch-inference]: 7 original-first fixtures agree"
