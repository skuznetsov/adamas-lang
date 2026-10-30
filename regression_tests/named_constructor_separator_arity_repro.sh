#!/usr/bin/env bash
# Bare named-only `*` must not erase finite positional arity from `new` overloads.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-180}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
ONLY_CASES="${ONLY_CASES:-all}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-constructor-separator-arity.XXXXXX")"

cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 || "${KEEP_ARTIFACTS:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ "$ORIGINAL_ONLY" != "0" && "$ORIGINAL_ONLY" != "1" ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -d "$CRYSTAL_STDLIB" ]]; then
  echo "ERROR: safe runner, installed Crystal, or Crystal stdlib is unavailable" >&2
  echo "Usage: ORIGINAL_ONLY=1 ONLY_CASES=all ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != "1" && ! -x "$ADAMAS_BIN" ]]; then
  echo "ERROR: candidate compiler is unavailable" >&2
  echo "Usage: ADAMAS_BIN=/path/to/adamas ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0" >&2
  exit 2
fi

ALL_CASES=(factory_size_first factory_value_first factory_declarations_reversed factory_true_rest factory_default_fixed_first factory_default_default_first missing_size wrong_size_type typed_rest_empty_rejected typed_rest_wrong_element_rejected untyped_rest_empty_accepted typed_rest_nonempty_body tuple_splat_rest_empty_accepted tuple_element_rest_empty_rejected tuple_element_rest_one_accepted)
if [[ "$ONLY_CASES" == "all" ]]; then
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
    if [[ "$known" != "1" ]]; then
      printf 'ERROR: unknown ONLY_CASES entry: %s\nAvailable: %s\n' \
        "$selected" "${ALL_CASES[*]}" >&2
      exit 2
    fi
  done
fi

write_source() {
  local name="$1" path="$WORK_DIR/$1.cr"
  cat >"$path" <<'CRYSTAL'
@[Link("c")]
lib NamedConstructorOutput
  fun putchar(value : Int32) : Int32
end
CRYSTAL

  case "$name" in
    untyped_rest_empty_accepted|typed_rest_nonempty_body|tuple_splat_rest_empty_accepted|tuple_element_rest_empty_rejected|tuple_element_rest_one_accepted)
      cat >>"$path" <<'CRYSTAL'
# Minimal stock Tuple#size support for the empty-prelude fixture.
struct Tuple
  def size
    {{T.size}}
  end
end
CRYSTAL
      ;;
  esac

  cat >>"$path" <<'CRYSTAL'

class NamedConstructorProbe
  def initialize(pointer : Bool, size : Int32, *, read_only = false)
  end
CRYSTAL

  case "$name" in
    factory_declarations_reversed)
      cat >>"$path" <<'CRYSTAL'
  def self.new(size : Int32, value : Int32, *, read_only = false) : Int32
    66
  end

  def self.new(size : Int32, *, read_only = false) : Int32
    65
  end
CRYSTAL
      ;;
    factory_true_rest)
      cat >>"$path" <<'CRYSTAL'
  def self.new(size : Int32, *values : Int32, read_only = false) : Int32
    67
  end

  def self.new(size : Int32, *, read_only = false) : Int32
    65
  end

  def self.new(size : Int32, value : Int32, *, read_only = false) : Int32
    66
  end
CRYSTAL
      ;;
    factory_default_fixed_first)
      cat >>"$path" <<'CRYSTAL'
  def self.new(size : Int32, *, read_only = false) : Int32
    65
  end

  def self.new(size : Int32, value : Int32 = 67, *, read_only = false) : Int32
    value
  end
CRYSTAL
      ;;
    factory_default_default_first)
      cat >>"$path" <<'CRYSTAL'
  def self.new(size : Int32, value : Int32 = 67, *, read_only = false) : Int32
    value
  end

  def self.new(size : Int32, *, read_only = false) : Int32
    65
  end
CRYSTAL
      ;;
    typed_rest_empty_rejected|typed_rest_wrong_element_rejected|untyped_rest_empty_accepted|typed_rest_nonempty_body|tuple_splat_rest_empty_accepted|tuple_element_rest_empty_rejected|tuple_element_rest_one_accepted)
      :
      ;;
    *)
      cat >>"$path" <<'CRYSTAL'
  def self.new(size : Int32, *, read_only = false) : Int32
    65
  end

  def self.new(size : Int32, value : Int32, *, read_only = false) : Int32
    66
  end
CRYSTAL
      ;;
  esac

  cat >>"$path" <<'CRYSTAL'
end

CRYSTAL
  case "$name" in
    factory_size_first)
      cat >>"$path" <<'CRYSTAL'
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, read_only: true))
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, 2, read_only: true))
NamedConstructorOutput.putchar(10)
CRYSTAL
      ;;
    factory_declarations_reversed)
      cat >>"$path" <<'CRYSTAL'
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, read_only: true))
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, 2, read_only: true))
NamedConstructorOutput.putchar(10)
CRYSTAL
      ;;
    factory_true_rest)
      cat >>"$path" <<'CRYSTAL'
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, read_only: true))
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, 2, read_only: true))
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, 2, 3, read_only: true))
NamedConstructorOutput.putchar(10)
CRYSTAL
      ;;
    factory_default_fixed_first|factory_default_default_first)
      cat >>"$path" <<'CRYSTAL'
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, read_only: true))
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, 66, read_only: true))
NamedConstructorOutput.putchar(10)
CRYSTAL
      ;;
    factory_value_first)
      cat >>"$path" <<'CRYSTAL'
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, 2, read_only: true))
NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, read_only: true))
NamedConstructorOutput.putchar(10)
CRYSTAL
      ;;
    missing_size)
      cat >>"$path" <<'CRYSTAL'
NamedConstructorProbe.new(read_only: true)
CRYSTAL
      ;;
    wrong_size_type)
      cat >>"$path" <<'CRYSTAL'
NamedConstructorProbe.new(true, read_only: true)
CRYSTAL
      ;;
    typed_rest_empty_rejected)
      cat >>"$path" <<'CRYSTAL'
class NamedConstructorProbe
  def self.new(size : Int32, *values : Int32, read_only = false) : Int32
    65
  end
end

NamedConstructorProbe.new(1, read_only: true)
CRYSTAL
      ;;
    typed_rest_wrong_element_rejected)
      cat >>"$path" <<'CRYSTAL'
class NamedConstructorProbe
  def self.new(size : Int32, *values : Int32, read_only = false) : Int32
    65
  end
end

NamedConstructorProbe.new(1, true, read_only: true)
CRYSTAL
      ;;
    untyped_rest_empty_accepted)
      cat >>"$path" <<'CRYSTAL'
class NamedConstructorProbe
  def self.new(size : Int32, *values, read_only = false) : Int32
    if read_only
      65 &+ values.size
    else
      70 &+ values.size
    end
  end
end

NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, read_only: true))
NamedConstructorOutput.putchar(10)
CRYSTAL
      ;;
    typed_rest_nonempty_body)
      cat >>"$path" <<'CRYSTAL'
class NamedConstructorProbe
  def self.new(size : Int32, *values : Int32, read_only = false) : Int32
    if read_only
      65 &+ values.size
    else
      70 &+ values.size
    end
  end
end

NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, 2, 3, read_only: true))
NamedConstructorOutput.putchar(10)
CRYSTAL
      ;;
    tuple_splat_rest_empty_accepted)
      cat >>"$path" <<'CRYSTAL'
class NamedConstructorProbe
  def self.new(size : Int32, *values : *Tuple(), read_only = false) : Int32
    if read_only
      65 &+ values.size
    else
      70 &+ values.size
    end
  end
end

NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, read_only: true))
NamedConstructorOutput.putchar(10)
CRYSTAL
      ;;
    tuple_element_rest_empty_rejected)
      cat >>"$path" <<'CRYSTAL'
class NamedConstructorProbe
  def self.new(size : Int32, *values : Tuple(), read_only = false) : Int32
    if read_only
      65 &+ values.size
    else
      70 &+ values.size
    end
  end
end

NamedConstructorProbe.new(1, read_only: true)
CRYSTAL
      ;;
    tuple_element_rest_one_accepted)
      cat >>"$path" <<'CRYSTAL'
class NamedConstructorProbe
  def self.new(size : Int32, *values : Tuple(), read_only = false) : Int32
    if read_only
      65 &+ values.size
    else
      70 &+ values.size
    end
  end
end

# An empty tuple has no literal syntax; an empty untyped rest produces it.
def named_constructor_empty_tuple(*values)
  values
end

NamedConstructorOutput.putchar(NamedConstructorProbe.new(1, named_constructor_empty_tuple, read_only: true))
NamedConstructorOutput.putchar(10)
CRYSTAL
      ;;
    *)
      printf 'ERROR: no source writer for case %s\n' "$name" >&2
      return 2
      ;;
  esac
}

compile_one() {
  local stage="$1" name="$2" source="$WORK_DIR/$2.cr"
  local binary="$WORK_DIR/$stage-$name.bin" log="$WORK_DIR/$stage-$name.build.log"
  local cache="$WORK_DIR/$stage-$name.cache" rc=0
  local -a mode_env
  mkdir -p "$cache"
  if [[ "$stage" == "original" ]]; then
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" build --prelude=empty --no-debug "$source" \
      -o "$binary" --link-flags=-fuse-ld=/usr/bin/ld >"$log" 2>&1 || rc=$?
  else
    if [[ "$stage" == "candidate-eager" ]]; then
      mode_env=(env ADAMAS_EAGER_CLASSVAR_INIT=1)
    else
      mode_env=(env -u ADAMAS_EAGER_CLASSVAR_INIT)
    fi
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      "${mode_env[@]}" "$SAFE_RUNNER" "$ADAMAS_BIN" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" "$source" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1 || rc=$?
  fi
  printf '%s\n' "$rc" >"$WORK_DIR/$stage-$name.build.status"
  printf '%s\n' "$binary"
}

check_positive() {
  local stage="$1" name="$2" expected="$3" binary log stdout rc
  binary="$(compile_one "$stage" "$name")"
  log="$WORK_DIR/$stage-$name.build.log"
  rc="$(cat "$WORK_DIR/$stage-$name.build.status")"
  if [[ "$rc" != "0" ]]; then
    cat "$log" >&2
    printf 'FAIL %s %s: expected successful compile\n' "$stage" "$name" >&2
    return 1
  fi
  log="$WORK_DIR/$stage-$name.run.log" stdout="$WORK_DIR/$stage-$name.stdout"
  rc=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.run.resources.json" \
    "$SAFE_RUNNER" "$binary" 10 512 >"$stdout" 2>"$log" || rc=$?
  if [[ "$rc" != "0" ]] || ! rg -Fq '[EXIT: 0]' "$log"; then
    cat "$log" "$stdout" >&2
    printf 'FAIL %s %s: native run did not exit zero\n' "$stage" "$name" >&2
    return 1
  fi
  printf '%s\n' "$expected" >"$WORK_DIR/$name.expected"
  if ! diff -u "$WORK_DIR/$name.expected" "$stdout"; then
    printf 'FAIL %s %s: stdout differed from expected factory overloads\n' \
      "$stage" "$name" >&2
    return 1
  fi
  if [[ "$stage" != "original" ]] && ! diff -u "$WORK_DIR/original-$name.stdout" "$stdout"; then
    printf 'FAIL %s %s: stdout differed from original Crystal\n' "$stage" "$name" >&2
    return 1
  fi
  printf 'PASS %s %s output=%q\n' "$stage" "$name" "$expected"
}

check_rejected() {
  local stage="$1" name="$2" binary log rc
  binary="$(compile_one "$stage" "$name")"
  log="$WORK_DIR/$stage-$name.build.log"
  rc="$(cat "$WORK_DIR/$stage-$name.build.status")"
  if [[ "$rc" != "1" ]] || ! rg -qi -- \
    'no overload matches|wrong number of arguments|missing argument|argument.*(type|must be)|type restriction|does not match|expected .* (got|not)' "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: expected constructor overload rejection (exit 1)\n' \
      "$stage" "$name" >&2
    return 1
  fi
  if rg -qi -- \
    'syntax error|parser errors|internal compiler error|unhandled exception|timed out|resource limit|undefined (constant|method)|unknown identifier' "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: rejection was not a source-level overload result\n' \
      "$stage" "$name" >&2
    return 1
  fi
  printf 'PASS %s %s rejected invalid constructor arguments\n' "$stage" "$name"
}

for name in "${SELECTED_CASES[@]}"; do
  write_source "$name"
  case "$name" in
    missing_size|wrong_size_type|typed_rest_empty_rejected|typed_rest_wrong_element_rejected|tuple_element_rest_empty_rejected)
      check_rejected original "$name"
      if [[ "$ORIGINAL_ONLY" != "1" ]]; then
        check_rejected candidate-lazy "$name"
        check_rejected candidate-eager "$name"
      fi
      ;;
    *)
      case "$name" in
        factory_value_first) expected="BA" ;;
        factory_true_rest) expected="ABC" ;;
        factory_default_fixed_first|factory_default_default_first) expected="CB" ;;
        untyped_rest_empty_accepted|tuple_splat_rest_empty_accepted) expected="A" ;;
        typed_rest_nonempty_body) expected="C" ;;
        tuple_element_rest_one_accepted) expected="B" ;;
        *) expected="AB" ;;
      esac
      # Qualify native output with original Crystal before candidate modes.
      check_positive original "$name" "$expected"
      if [[ "$ORIGINAL_ONLY" != "1" ]]; then
        check_positive candidate-lazy "$name" "$expected"
        check_positive candidate-eager "$name" "$expected"
      fi
      ;;
  esac
done

if [[ "$ORIGINAL_ONLY" == "1" ]]; then
  printf 'PASS: original Crystal qualified named-constructor separator arity cases (%s)\n' \
    "${SELECTED_CASES[*]}"
else
  printf 'PASS: named-constructor separator arity cases match original Crystal (%s)\n' \
    "${SELECTED_CASES[*]}"
fi
