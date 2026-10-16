#!/usr/bin/env bash
# Compare concrete and generic T{key => value} lowering with Crystal 1.21.
# Pass the Adamas compiler binary as the first argument.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${1:-${ADAMAS_BIN:-}}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
ORIGINAL_CRYSTAL_PATH="${ORIGINAL_CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
ADAMAS_EXTRA_CRYSTAL_PATH="${ADAMAS_EXTRA_CRYSTAL_PATH:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-hash-literal-contract.XXXXXX")"
WORK_DIR="$(cd "$WORK_DIR" && pwd -P)"

cleanup() {
  local rc=$?
  if [[ $rc -ne 0 || "${KEEP_WORK_DIR:-0}" == "1" ]]; then
    printf 'ARTIFACT_DIR=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 2
}

if [[ -z "$ADAMAS_BIN" || ! -x "$ADAMAS_BIN" ]]; then
  fail "pass an executable Adamas compiler as the first argument (or ADAMAS_BIN)"
fi
if [[ ! -x "$ORIGINAL_CRYSTAL" ]]; then
  fail "original Crystal compiler is not executable: $ORIGINAL_CRYSTAL"
fi
ADAMAS_BIN="$(cd "$(dirname "$ADAMAS_BIN")" && pwd -P)/$(basename "$ADAMAS_BIN")"
ORIGINAL_CRYSTAL="$(cd "$(dirname "$ORIGINAL_CRYSTAL")" && pwd -P)/$(basename "$ORIGINAL_CRYSTAL")"

mkdir -p "$WORK_DIR/source" "$WORK_DIR/original" "$WORK_DIR/adamas"

ADAMAS_CRYSTAL_PATH="$ORIGINAL_CRYSTAL_PATH"
if [[ -n "$ADAMAS_EXTRA_CRYSTAL_PATH" ]]; then
  ADAMAS_CRYSTAL_PATH="$ADAMAS_CRYSTAL_PATH:$ADAMAS_EXTRA_CRYSTAL_PATH"
fi

cat >"$WORK_DIR/source/http_headers.cr" <<'CRYSTAL'
require "http/headers"

headers = HTTP::Headers{"User-Agent" => "LavinMQ"}
puts headers["User-Agent"]
CRYSTAL

cat >"$WORK_DIR/source/ordered_effects.cr" <<'CRYSTAL'
class NamedHashTraceLog
  @@events : Array(String) = [] of String

  def self.add(value : String)
    @@events << value
  end

  def self.events : Array(String)
    @@events
  end
end

def named_hash_key(label : String) : String
  NamedHashTraceLog.add("key:" + label)
  label == "dup" ? "same" : label
end

def named_hash_value(label : String) : String
  NamedHashTraceLog.add("value:" + label)
  label
end

class NamedHashTraceMap
  @entries : Hash(String, String)

  def initialize
    NamedHashTraceLog.add("new")
    @entries = Hash(String, String).new
  end

  def []=(key : String, value : String) : String
    NamedHashTraceLog.add("set:" + key + ":" + value)
    @entries[key] = value
    "setter-result"
  end

  def [](key : String) : String
    @entries[key]
  end

  def to_s(io : IO) : Nil
    io << "container"
  end
end

result = NamedHashTraceMap{
  named_hash_key("dup") => named_hash_value("first"),
  named_hash_key("dup") => named_hash_value("last"),
}
puts result.to_s
puts result["same"]
puts NamedHashTraceLog.events.join(",")
CRYSTAL

cat >"$WORK_DIR/source/direct_local_order.cr" <<'CRYSTAL'
class NamedHashMutationProbe
  @@before_new : Proc(Nil)? = nil
  @@seen : String = ""

  def self.before_new=(callback : Proc(Nil))
    @@before_new = callback
  end

  def self.seen : String
    @@seen
  end

  def initialize
    @@before_new.not_nil!.call
  end

  def []=(key : String, value : String) : String
    @@seen = value
    "setter-result"
  end
end

source = "before"
NamedHashMutationProbe.before_new = -> { source = "after" }
NamedHashMutationProbe{"key" => source}
puts NamedHashMutationProbe.seen
CRYSTAL

cat >"$WORK_DIR/source/generic_inference.cr" <<'CRYSTAL'
explicit = Hash(String, Int32){"explicit" => 1}
inferred = Hash{"inferred" => 2}
puts explicit["explicit"]
puts inferred["inferred"]
CRYSTAL

cat >"$WORK_DIR/source/empty_generic_new.cr" <<'CRYSTAL'
empty = Hash(String, Int32){} of String => Int32
puts empty.size
CRYSTAL

extract_stdout() {
  awk '
    /^=== STDOUT ===$/ { in_stdout = 1; next }
    /^=== STDERR ===$/ { exit }
    in_stdout { print }
  ' "$1"
}

run_original() {
  local name="$1" source="$2" log="$WORK_DIR/original/$1.log" rc
  set +e
  CRYSTAL_PATH="$ORIGINAL_CRYSTAL_PATH" \
    "$RUN_SAFE" "$ORIGINAL_CRYSTAL" 240 8192 \
    run --link-flags=-fuse-ld=/usr/bin/ld "$source" >"$log" 2>&1
  rc=$?
  set -e
  printf '%s\n' "$rc" >"$WORK_DIR/original/$name.exit"
  if [[ $rc -ne 0 ]]; then
    tail -n 20 "$log" >&2
    fail "original Crystal rejected $name"
  fi
  extract_stdout "$log" >"$WORK_DIR/original/$name.stdout"
}

run_adamas() {
  local name="$1" source="$2" log="$WORK_DIR/adamas/$1.compile.log" rc binary
  binary="$WORK_DIR/adamas/$name.bin"
  set +e
  CRYSTAL_PATH="$ADAMAS_CRYSTAL_PATH" \
  ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
    "$RUN_SAFE" "$ADAMAS_BIN" 240 8192 \
    "$source" --no-llvm-cache --no-ast-cache --stats -o "$binary" >"$log" 2>&1
  rc=$?
  set -e
  printf '%s\n' "$rc" >"$WORK_DIR/adamas/$name.compile.exit"
  if [[ $rc -ne 0 ]]; then
    tail -n 24 "$log" >&2
    fail "Adamas failed to compile $name"
  fi

  log="$WORK_DIR/adamas/$name.run.log"
  set +e
  "$RUN_SAFE" "$binary" 30 2048 >"$log" 2>&1
  rc=$?
  set -e
  printf '%s\n' "$rc" >"$WORK_DIR/adamas/$name.run.exit"
  if [[ $rc -ne 0 ]]; then
    tail -n 24 "$log" >&2
    fail "Adamas output for $name exited with $rc"
  fi
  extract_stdout "$log" >"$WORK_DIR/adamas/$name.stdout"
}

for name in http_headers ordered_effects direct_local_order generic_inference empty_generic_new; do
  run_original "$name" "$WORK_DIR/source/$name.cr"
  run_adamas "$name" "$WORK_DIR/source/$name.cr"
  if ! cmp -s "$WORK_DIR/original/$name.stdout" "$WORK_DIR/adamas/$name.stdout"; then
    printf 'Original stdout for %s:\n' "$name" >&2
    cat "$WORK_DIR/original/$name.stdout" >&2
    printf 'Adamas stdout for %s:\n' "$name" >&2
    cat "$WORK_DIR/adamas/$name.stdout" >&2
    diff -u "$WORK_DIR/original/$name.stdout" "$WORK_DIR/adamas/$name.stdout" >&2 || true
    fail "stdout mismatch for $name"
  fi
done

printf 'PASS: named hash literals match Crystal 1.21 across HTTP::Headers, evaluation order, duplicate setters, local mutation, generic inference, and empty construction.\n'
