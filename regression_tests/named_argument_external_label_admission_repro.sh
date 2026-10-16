#!/usr/bin/env bash
# Named arguments bind by external label; internal variable names are not aliases.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-}"

if [[ -z "$CRYSTAL_STDLIB" ]]; then
  search_dir="$ROOT_DIR"
  for _ in 1 2 3 4 5 6; do
    for candidate in \
      "$search_dir/crystal/src" \
      "$search_dir/Crystal/crystal/src" \
      "$search_dir/Projects/Crystal/crystal/src"; do
      if [[ -d "$candidate" ]]; then
        CRYSTAL_STDLIB="$candidate"
        break 2
      fi
    done
    parent_dir="$(dirname "$search_dir")"
    [[ "$parent_dir" != "$search_dir" ]] || break
    search_dir="$parent_dir"
  done
fi

if [[ -z "$CRYSTAL_STDLIB" && -x "$ORIGINAL_CRYSTAL_BIN" ]]; then
  CRYSTAL_STDLIB="$($ORIGINAL_CRYSTAL_BIN env CRYSTAL_PATH 2>/dev/null || true)"
fi

[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -x "$SAFE_RUNNER" ]] || {
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-label-admission.XXXXXX")"
cleanup() {
  local status=$?
  local cache_dir
  for cache_dir in "$WORK_DIR"/*.crystal-cache; do
    [[ -e "$cache_dir" ]] && rm -rf "$cache_dir"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

class DirectLabels
  def combine(*, left external_left : Int32, right external_right : Int32, fallback : Int32 = 5) : Int32
    external_left * 100 + external_right * 10 + fallback
  end

  def external(*, public internal : Int32) : Int32
    internal
  end

  def ordinary(value : Int32) : Int32
    value
  end
end

class LabelBase
  def inherited(*, visible value : Int32, mode : Int32 = 7) : Int32
    value * 10 + mode
  end
end

class LabelChild < LabelBase
end

class KeywordCatchall
  def accept(**options) : Int32
    61
  end
end

class BlockLabelBase
  def choose(*, public value : Int32, mode : Int32 = 0) : Int32
    yield value + mode
  end
end

class BlockLabelChild < BlockLabelBase
end

def emit(value : Int32)
  C.putchar(48 + value // 100)
  C.putchar(48 + value // 10 % 10)
  C.putchar(48 + value % 10)
  C.putchar(10)
end

direct = DirectLabels.new
emit(direct.combine(right: 2, left: 1))
emit(direct.combine(left: 1, right: 2))
emit(direct.external(public: 4))
emit(direct.ordinary(value: 9))
emit(KeywordCatchall.new.accept(unrecognized: 1))
emit(BlockLabelBase.new.choose(public: 2) { |item| item + 1 })
emit(BlockLabelChild.new.choose(public: 3, mode: 1) { |item| item + 1 })
CRYSTAL
cat >"$WORK_DIR/expected" <<'EXPECTED'
125
125
004
009
061
003
005
EXPECTED

status=0
env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original-positive.crystal-cache" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/original-positive.build.resources" \
  "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/positive.cr" \
  -o "$WORK_DIR/original-positive.bin" --link-flags=-fuse-ld=/usr/bin/ld \
  >"$WORK_DIR/original-positive.build.log" 2>&1 || status=$?
[[ "$status" == 0 ]] || { cat "$WORK_DIR/original-positive.build.log" >&2; exit 1; }
RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/original-positive.bin" 10 512 \
  >"$WORK_DIR/original-positive.stdout" 2>"$WORK_DIR/original-positive.run.log" || status=$?
[[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/original-positive.run.log" || {
  cat "$WORK_DIR/original-positive.run.log" >&2
  exit 1
}
diff -u "$WORK_DIR/expected" "$WORK_DIR/original-positive.stdout"

status=0
env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate-positive.crystal-cache" \
  ADAMAS_LLVM_CACHE=0 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate-positive.build.resources" \
  "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/positive.cr" --no-debug --no-prelude \
  --no-ast-cache --no-llvm-cache -o "$WORK_DIR/candidate-positive.bin" \
  >"$WORK_DIR/candidate-positive.build.log" 2>&1 || status=$?
[[ "$status" == 0 ]] || { cat "$WORK_DIR/candidate-positive.build.log" >&2; exit 1; }
RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/candidate-positive.bin" 10 512 \
  >"$WORK_DIR/candidate-positive.stdout" 2>"$WORK_DIR/candidate-positive.run.log" || status=$?
[[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/candidate-positive.run.log" || {
  cat "$WORK_DIR/candidate-positive.run.log" >&2
  exit 1
}
diff -u "$WORK_DIR/expected" "$WORK_DIR/candidate-positive.stdout"

check_rejected() {
  local shape="$1"
  local source="$2"
  printf '%s\n' "$source" >"$WORK_DIR/$shape.cr"

  local original_status=0
  env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/$shape.original.crystal-cache" \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$shape.original.resources" \
    "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/$shape.cr" \
    -o "$WORK_DIR/$shape.original.bin" --link-flags=-fuse-ld=/usr/bin/ld \
    >"$WORK_DIR/$shape.original.log" 2>&1 || original_status=$?
  if [[ "$original_status" == 0 ]]; then
    cat "$WORK_DIR/$shape.original.log" >&2
    echo "original Crystal accepted invalid label shape: $shape" >&2
    return 1
  fi
  if ! grep -Fq "Error: missing argument: public" "$WORK_DIR/$shape.original.log"; then
    cat "$WORK_DIR/$shape.original.log" >&2
    echo "original Crystal rejected $shape for an unexpected reason" >&2
    return 1
  fi

  local candidate_status=0
  env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/$shape.candidate.crystal-cache" \
    ADAMAS_LLVM_CACHE=0 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$shape.candidate.resources" \
    "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/$shape.cr" --no-debug --no-prelude \
    --no-ast-cache --no-llvm-cache -o "$WORK_DIR/$shape.candidate.bin" \
    >"$WORK_DIR/$shape.candidate.log" 2>&1 || candidate_status=$?
  if [[ "$candidate_status" == 0 ]]; then
    echo "candidate admitted invalid external label: $shape" >&2
    return 1
  fi
  if ! grep -Fq "no overload matches named arguments" "$WORK_DIR/$shape.candidate.log"; then
    cat "$WORK_DIR/$shape.candidate.log" >&2
    echo "candidate rejected $shape for an unexpected reason" >&2
    return 1
  fi
}

check_rejected direct_internal_label $'class DirectBadLabel\n  def choose(*, public value : Int32) : Int32\n    value\n  end\nend\nDirectBadLabel.new.choose(value: 2)'
check_rejected direct_unknown_label $'class DirectUnknownLabel\n  def choose(*, public value : Int32) : Int32\n    value\n  end\nend\nDirectUnknownLabel.new.choose(other: 2)'
check_rejected inherited_internal_label $'class InheritedBadBase\n  def choose(*, public value : Int32) : Int32\n    value\n  end\nend\nclass InheritedBadLabel < InheritedBadBase\nend\nInheritedBadLabel.new.choose(value: 2)'
check_rejected inherited_unknown_label $'class InheritedUnknownBase\n  def choose(*, public value : Int32) : Int32\n    value\n  end\nend\nclass InheritedUnknownLabel < InheritedUnknownBase\nend\nInheritedUnknownLabel.new.choose(other: 2)'
check_rejected direct_block_internal_label $'class DirectBadBlockLabel\n  def choose(*, public value : Int32) : Int32\n    yield value\n  end\nend\nDirectBadBlockLabel.new.choose(value: 2) { |item| item + 1 }'
check_rejected direct_block_unknown_label $'class DirectUnknownBlockLabel\n  def choose(*, public value : Int32) : Int32\n    yield value\n  end\nend\nDirectUnknownBlockLabel.new.choose(other: 2) { |item| item + 1 }'
check_rejected inherited_block_internal_label $'class InheritedBadBlockBase\n  def choose(*, public value : Int32) : Int32\n    yield value\n  end\nend\nclass InheritedBadBlockChild < InheritedBadBlockBase\nend\nInheritedBadBlockChild.new.choose(value: 2) { |item| item + 1 }'
check_rejected inherited_block_unknown_label $'class InheritedUnknownBlockBase\n  def choose(*, public value : Int32) : Int32\n    yield value\n  end\nend\nclass InheritedUnknownBlockChild < InheritedUnknownBlockBase\nend\nInheritedUnknownBlockChild.new.choose(other: 2) { |item| item + 1 }'

printf 'PASS: external-label admission matches Crystal; aliases, defaults, reordering, **kwargs, and inline block calls preserved\n'
