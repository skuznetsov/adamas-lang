#!/usr/bin/env bash
# Check macro Array#select/reject shorthand blocks against stock Crystal.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
elif [[ -n "$ORIGINAL_CRYSTAL_BIN" ]]; then
  CRYSTAL_STDLIB="$("$ORIGINAL_CRYSTAL_BIN" env CRYSTAL_PATH)"
else
  CRYSTAL_STDLIB=""
fi
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-180}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
ONLY_CASES="${ONLY_CASES:-all}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-shorthand-filter.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache-*
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
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
if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -d "$CRYSTAL_STDLIB" || ! -f "$CRYSTAL_STDLIB/empty.cr" ]]; then
  echo "ERROR: safe runner, original Crystal, or stock Crystal stdlib is unavailable" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != 1 && ! -x "$ADAMAS_BIN" ]]; then
  echo "ERROR: candidate Adamas compiler is unavailable: $ADAMAS_BIN" >&2
  exit 2
fi

ALL_CASES=(explicit_control shorthand_select shorthand_reject chained_predicate reflection_dispatch cross_file_annotation_argument module_annotation_include_first module_annotation_include_after_field)
if [[ "$ONLY_CASES" == all ]]; then
  SELECTED_CASES=("${ALL_CASES[@]}")
else
  normalized_cases="${ONLY_CASES//,/ }"
  read -r -a SELECTED_CASES <<<"$normalized_cases"
  if [[ "${#SELECTED_CASES[@]}" -eq 0 ]]; then
    echo "ERROR: ONLY_CASES must be all or a comma/space-separated case list" >&2
    exit 2
  fi
  for selected in "${SELECTED_CASES[@]}"; do
    known=0
    for available in "${ALL_CASES[@]}"; do
      [[ "$selected" == "$available" ]] && known=1
    done
    if [[ "$known" != 1 ]]; then
      printf 'ERROR: unknown ONLY_CASES entry: %s\nAvailable: %s\n' \
        "$selected" "${ALL_CASES[*]}" >&2
      exit 2
    fi
  done
fi

write_source() {
  local name="$1"
  local path="$WORK_DIR/$name.cr"

  if [[ "$name" == module_annotation_include_first || "$name" == module_annotation_include_after_field ]]; then
    cat >"$path" <<'CRYSTAL'
@[Link("c")]
lib MacroFilterNative
  fun putchar(value : Int32) : Int32
end

annotation MacroFilterOpt
end

module MacroFilterIncludeSource
  @[MacroFilterOpt(section: "module", code: 65)]
  @entry : Int32 = 1
end

class MacroFilterProbe
CRYSTAL
    if [[ "$name" == module_annotation_include_first ]]; then
      cat >>"$path" <<'CRYSTAL'
  include MacroFilterIncludeSource

  @[MacroFilterOpt(section: "class", code: 66)]
  @entry : Int32 = 2
CRYSTAL
    else
      cat >>"$path" <<'CRYSTAL'
  @[MacroFilterOpt(section: "class", code: 66)]
  @entry : Int32 = 2

  include MacroFilterIncludeSource
CRYSTAL
    fi
    cat >>"$path" <<'CRYSTAL'

  def run
    MacroFilterNative.putchar({{@type.instance_vars.first.annotation(MacroFilterOpt)[:code]}})
    MacroFilterNative.putchar(64 | {{@type.instance_vars.first.annotations(MacroFilterOpt).size}})
  end
end

MacroFilterProbe.new.run
MacroFilterNative.putchar(10)
CRYSTAL
    return
  fi

  if [[ "$name" == cross_file_annotation_argument ]]; then
    cat >"$WORK_DIR/${name}_support.cr" <<'CRYSTAL'
annotation MacroFilterOpt
end

class MacroFilterProbe
  @[MacroFilterOpt(section: "main", code: 65)]
  @main_value : Int32 = 1
end
CRYSTAL
    cat >"$path" <<CRYSTAL
@[Link("c")]
lib MacroFilterNative
  fun putchar(value : Int32) : Int32
end

require "./${name}_support"

class MacroFilterProbe
  def run
    MacroFilterNative.putchar({{@type.instance_vars.first.annotation(MacroFilterOpt)[:code]}})
  end
end

MacroFilterProbe.new.run
MacroFilterNative.putchar(10)
CRYSTAL
    return
  fi

  cat >"$path" <<'CRYSTAL'
@[Link("c")]
lib MacroFilterNative
  fun putchar(value : Int32) : Int32
end

annotation MacroFilterOpt
end

class MacroFilterProbe
  @[MacroFilterOpt(section: "main", code: 65)]
  @main_value : Int32 = 1

  @[MacroFilterOpt(section: "other", code: 66)]
  @other_value : Int32 = 2

  @plain_value : Bool = false
CRYSTAL

  case "$name" in
    explicit_control)
      cat >>"$path" <<'CRYSTAL'
  def run
    MacroFilterNative.putchar({{64 + @type.instance_vars.select { |ivar| ivar.type == Int32 }.size}})
  end
CRYSTAL
      ;;
    shorthand_select)
      cat >>"$path" <<'CRYSTAL'
  def run
    MacroFilterNative.putchar({{64 + @type.instance_vars.select(&.annotation(MacroFilterOpt)).size}})
  end
CRYSTAL
      ;;
    shorthand_reject)
      cat >>"$path" <<'CRYSTAL'
  def run
    MacroFilterNative.putchar({{64 + @type.instance_vars.reject(&.annotation(MacroFilterOpt).nil?).size}})
  end
CRYSTAL
      ;;
    chained_predicate)
      cat >>"$path" <<'CRYSTAL'
  def run
    MacroFilterNative.putchar({{64 + @type.instance_vars.reject(&.annotation(MacroFilterOpt).nil?).select(&.annotation(MacroFilterOpt)[:section].==("main")).size}})
  end
CRYSTAL
      ;;
    reflection_dispatch)
      cat >>"$path" <<'CRYSTAL'
  def parse_type(type : Int32.class)
    MacroFilterNative.putchar(65)
  end

  def run
    self.parse_type({{@type.instance_vars.select(&.annotation(MacroFilterOpt)).last.type}})
  end
CRYSTAL
      ;;
    cross_file_annotation_argument)
      # The source was emitted above so its annotation remains in a separate
      # parser arena when the reopened method performs macro reflection.
      ;;
  esac

  cat >>"$path" <<'CRYSTAL'
end

MacroFilterProbe.new.run
MacroFilterNative.putchar(10)
CRYSTAL
}

compile_one() {
  local stage="$1" name="$2" compiler="$3"
  local binary="$WORK_DIR/$stage-$name.bin"
  local log="$WORK_DIR/$stage-$name.build.log"
  local cache="$WORK_DIR/cache-$stage-$name"
  local status=0
  local -a command mode_env=()
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    command=(build --prelude=empty --no-debug "$WORK_DIR/$name.cr" -o "$binary" \
      "--link-flags=$LINK_FLAGS")
    env -u ADAMAS_EAGER_MONO -u ADAMAS_EAGER_HIR \
      CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "${command[@]}" >"$log" 2>&1 || status=$?
  else
    command=("$WORK_DIR/$name.cr" --no-prelude --no-debug --no-ast-cache \
      --no-llvm-cache -o "$binary")
    if [[ "$stage" == candidate-eager ]]; then
      mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    else
      mode_env=(env -u ADAMAS_EAGER_MONO -u ADAMAS_EAGER_HIR)
    fi
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" \
      "${mode_env[@]}" "$SAFE_RUNNER" "$compiler" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" "${command[@]}" >"$log" 2>&1 || status=$?
  fi

  if [[ "$status" != 0 ]] || ! rg -q '^\[EXIT: 0\]( |$)' "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: compile did not exit zero\n' "$stage" "$name" >&2
    return 1
  fi
  rm -rf -- "$cache"
  printf '%s\n' "$binary"
}

run_case() {
  local stage="$1" name="$2" binary="$3" expected="$4"
  local stdout="$WORK_DIR/$stage-$name.stdout"
  local log="$WORK_DIR/$stage-$name.run.log"
  local status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.resources.json" \
    "$SAFE_RUNNER" "$binary" 10 1024 >"$stdout" 2>"$log" || status=$?
  if [[ "$status" != 0 ]] || ! rg -q '^\[EXIT: 0\]( |$)' "$log"; then
    cat "$log" >&2
    cat "$stdout" >&2
    printf 'FAIL %s %s: native run did not exit zero\n' "$stage" "$name" >&2
    return 1
  fi
  printf '%s\n' "$expected" >"$WORK_DIR/$name.expected"
  if ! diff -u "$WORK_DIR/$name.expected" "$stdout"; then
    printf 'FAIL %s %s: stdout differed from expected output\n' "$stage" "$name" >&2
    return 1
  fi
  if [[ "$stage" != original ]] && ! diff -u "$WORK_DIR/original-$name.stdout" "$stdout"; then
    printf 'FAIL %s %s: stdout differed from original Crystal\n' "$stage" "$name" >&2
    return 1
  fi
  printf 'PASS %s %s output=%q\n' "$stage" "$name" "$expected"
}

expected_output() {
  case "$1" in
    explicit_control|shorthand_select|shorthand_reject) printf 'B\n' ;;
    chained_predicate) printf 'A\n' ;;
    reflection_dispatch|cross_file_annotation_argument) printf 'A\n' ;;
    module_annotation_include_first|module_annotation_include_after_field) printf 'BA\n' ;;
  esac
}

for name in "${SELECTED_CASES[@]}"; do
  write_source "$name"
done

# Qualify every source with stock Crystal before asking the candidate to run it.
for name in "${SELECTED_CASES[@]}"; do
  binary="$(compile_one original "$name" "$ORIGINAL_CRYSTAL_BIN")"
  run_case original "$name" "$binary" "$(expected_output "$name")"
done

if [[ "$ORIGINAL_ONLY" == 1 ]]; then
  printf 'PASS: original Crystal qualified macro shorthand cases (%s)\n' \
    "${SELECTED_CASES[*]}"
  exit 0
fi

candidate_failures=0
for mode in lazy eager; do
  stage="candidate-$mode"
  for name in "${SELECTED_CASES[@]}"; do
    if binary="$(compile_one "$stage" "$name" "$ADAMAS_BIN")"; then
      if ! run_case "$stage" "$name" "$binary" "$(expected_output "$name")"; then
        candidate_failures=$((candidate_failures + 1))
      fi
    else
      candidate_failures=$((candidate_failures + 1))
    fi
  done
done

if [[ "$candidate_failures" -ne 0 ]]; then
  printf 'FAIL: candidate had %s lazy/eager macro shorthand mismatches\n' \
    "$candidate_failures" >&2
  exit 1
fi

printf 'PASS: macro shorthand filters match original Crystal (%s)\n' \
  "${SELECTED_CASES[*]}"
