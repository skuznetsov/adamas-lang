#!/usr/bin/env bash
# Omit impossible scalar case bodies only with registered source hierarchy evidence.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
elif [[ -d "$ROOT_DIR/../crystal/src" ]]; then
  CRYSTAL_STDLIB="$(cd "$ROOT_DIR/../crystal/src" && pwd -P)"
else
  echo "set CRYSTAL_PATH to the external Crystal stdlib source directory" >&2
  exit 2
fi
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -d "$CRYSTAL_STDLIB" ]] || exit 2

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/registered-scalar-disjoint.XXXXXX")"
cleanup() {
  local status=$?
  for name in struct_union class_union matching_scalar; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/struct_union.cr" <<'CRYSTAL'
struct DisjointCasePayload
end
def scalar_only(value : UInt8)
  STDOUT.write_byte(value)
end
def disjoint_case_probe(flag : Int32)
  value = if flag == 0
            'x'
          elsif flag == 1
            DisjointCasePayload.new
          else
            {"key", DisjointCasePayload.new}
          end
  case value
  when UInt8
    scalar_only(value)
  else
    puts "other"
  end
end
disjoint_case_probe(0)
disjoint_case_probe(1)
disjoint_case_probe(2)
CRYSTAL
cat >"$WORK_DIR/struct_union.expected" <<'EXPECTED'
other
other
other
EXPECTED
: >"$WORK_DIR/struct_union.stderr.expected"

cat >"$WORK_DIR/class_union.cr" <<'CRYSTAL'
class DisjointCaseReference
end
def only_scalar(value : Bool | Int64 | Float64 | Char | Symbol)
  puts "unexpected"
end
def class_case_probe(flag : Bool)
  value = flag ? DisjointCaseReference.new : {"key", 1}
  case value
  when Bool, Int64, Float64, Char, Symbol
    only_scalar(value)
  else
    puts "reference"
  end
end
class_case_probe(true)
class_case_probe(false)
CRYSTAL
cat >"$WORK_DIR/class_union.expected" <<'EXPECTED'
reference
reference
EXPECTED
: >"$WORK_DIR/class_union.stderr.expected"

cat >"$WORK_DIR/matching_scalar.cr" <<'CRYSTAL'
struct MatchingCasePayload
end
def only_byte(value : UInt8)
  puts value.to_i
end
def matching_case_probe(flag : Bool)
  value = flag ? MatchingCasePayload.new : 65_u8
  case value
  when UInt8
    only_byte(value)
  else
    puts "payload"
  end
end
matching_case_probe(true)
matching_case_probe(false)
CRYSTAL
cat >"$WORK_DIR/matching_scalar.expected" <<'EXPECTED'
payload
65
EXPECTED
: >"$WORK_DIR/matching_scalar.stderr.expected"

compile_run() {
  local name="$1" mode="$2" compiler="$3" status=0
  local source="$WORK_DIR/$name.cr" output="$WORK_DIR/$mode-$name.bin"
  local log="$WORK_DIR/$mode-$name.compile.log" cache="$WORK_DIR/$mode-$name.cache"
  if [[ "$mode" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$source" --no-debug \
      --link-flags=-fuse-ld=/usr/bin/ld -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-ast-cache --no-llvm-cache \
      --no-debug -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$mode/$name]: compile exited $status" >&2
    tail -30 "$log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.run.resources" \
    "$SAFE_RUNNER" "$output" 10 512 >"$WORK_DIR/$mode-$name.stdout" \
    2>"$WORK_DIR/$mode-$name.run.log"; then
    echo "FAIL[$mode/$name]: runtime failed" >&2
    cat "$WORK_DIR/$mode-$name.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$mode-$name.run.log"
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$mode-$name.stdout"
  awk '/^=== STDERR ===$/ { capture=1; next } /^\[EXIT: / { capture=0 } capture { print }' \
    "$WORK_DIR/$mode-$name.run.log" >"$WORK_DIR/$mode-$name.stderr"
  diff -u "$WORK_DIR/$name.stderr.expected" "$WORK_DIR/$mode-$name.stderr"
}

# Certify every fixture against the original before testing the candidate.
for name in struct_union class_union matching_scalar; do
  compile_run "$name" original "$ORIGINAL_CRYSTAL_BIN"
done
for name in struct_union class_union matching_scalar; do
  compile_run "$name" candidate "$COMPILER"
  echo "PASS[$name]: original and candidate stdout and stderr agree"
done
echo "PASS[registered-scalar-disjoint]: three original-first fixtures agree"
