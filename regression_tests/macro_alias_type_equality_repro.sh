#!/usr/bin/env bash
# Macro type equality must resolve visible aliases without capturing unrelated names.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${COMPILER:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$RUN_SAFE" && -x "$ORIGINAL" ]] || {
  echo "usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal CRYSTAL_PATH=/path/to/crystal/src $0 /path/to/adamas" >&2
  exit 2
}
if [[ "${ORIGINAL_ONLY:-0}" != 1 && ! -x "$COMPILER" ]]; then
  echo "usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0 /path/to/adamas" >&2
  exit 2
fi
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-alias-type-equality.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

# Preserve caller-selected CRYSTAL_PATH, PATH, SDKROOT, library paths, and
# compiler settings. Only supply Crystal's usual macOS linker override when
# the caller did not choose one.
if [[ -z "${ADAMAS_EXTRA_LINK_FLAGS:-}" && "$(uname -s)" == Darwin ]]; then
  export ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld
fi
link_flags=()
if [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]]; then
  link_flags+=("--link-flags=$ADAMAS_EXTRA_LINK_FLAGS")
fi

cat >"$WORK_DIR/fixture.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end

alias DirectWord = UInt64
alias FirstHop = DirectWord
alias SecondHop = FirstHop

module Types
  alias Word = UInt64
  alias ChainedWord = Word
end

module Stranger
  alias Wand = UInt64
end

class Wand
end

module Scope
  alias Word = UInt32
  module Types
    alias Word = UInt32
  end

  def self.emit_shadow
    {% if Word == UInt32 %}
      Probe.putchar(69)
    {% else %}
      Probe.putchar(88)
    {% end %}
  end

  def self.emit_qualified_shadow
    {% if Types::Word == UInt32 %}
      Probe.putchar(70)
    {% else %}
      Probe.putchar(88)
    {% end %}
  end

  def self.emit_rooted_outer
    {% if ::Types::Word == UInt64 %}
      Probe.putchar(71)
    {% else %}
      Probe.putchar(88)
    {% end %}
  end

end

def emit_unrelated_alias_shadow
  {% if Wand == UInt64 %}
      Probe.putchar(88)
  {% else %}
    Probe.putchar(73)
  {% end %}
end

def emit_direct
  {% if DirectWord == UInt64 %}
    Probe.putchar(65)
  {% else %}
    Probe.putchar(88)
  {% end %}
end

def emit_chained
  {% if SecondHop == UInt64 %}
    Probe.putchar(66)
  {% else %}
    Probe.putchar(88)
  {% end %}
end

def emit_qualified
  {% if Types::Word == UInt64 %}
    Probe.putchar(67)
  {% else %}
    Probe.putchar(88)
  {% end %}
end

def emit_qualified_chain
  {% if Types::ChainedWord == UInt64 %}
    Probe.putchar(68)
  {% else %}
    Probe.putchar(88)
  {% end %}
end

def emit_unequal
  {% if DirectWord == UInt32 %}
    Probe.putchar(88)
  {% else %}
    Probe.putchar(72)
  {% end %}
end

def emit_literal_integer
  {% if 1_i32 == 1_i64 %}
    Probe.putchar(74)
  {% else %}
    Probe.putchar(88)
  {% end %}
end

def emit_literal_string
  {% if "a" + "b" == "ab" %}
    Probe.putchar(75)
  {% else %}
    Probe.putchar(88)
  {% end %}
end

emit_direct
emit_chained
emit_qualified
emit_qualified_chain
Scope.emit_shadow
Scope.emit_qualified_shadow
Scope.emit_rooted_outer
emit_unequal
emit_unrelated_alias_shadow
emit_literal_integer
emit_literal_string
CRYSTAL

expected="ABCDEFGHIXK"
run_safe() {
  local label="$1"; shift
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
      CRYSTAL_CACHE_DIR="$WORK_DIR/$label.cache" \
      "$RUN_SAFE" "$@" >"$WORK_DIR/$label.stdout" 2>"$WORK_DIR/$label.stderr"; then
    cat "$WORK_DIR/$label.stderr" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$label.stderr"
}

# Establish the oracle first. Both compilers use the same no-prelude source and linker.
run_safe original_build "$ORIGINAL" 180 8192 build "$WORK_DIR/fixture.cr" \
  -o "$WORK_DIR/original.bin" --no-debug --prelude empty \
  "${link_flags[@]}"
run_safe original_run "$WORK_DIR/original.bin" 15 1024
printf '%s' "$expected" >"$WORK_DIR/expected.stdout"
diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/original_run.stdout"

if [[ "${ORIGINAL_ONLY:-0}" != 1 ]]; then
  run_safe candidate_build "$COMPILER" 180 8192 "$WORK_DIR/fixture.cr" \
    --no-prelude --no-ast-cache --no-llvm-cache --no-debug \
    -o "$WORK_DIR/candidate.bin"
  run_safe candidate_run "$WORK_DIR/candidate.bin" 15 1024
  diff -u "$WORK_DIR/original_run.stdout" "$WORK_DIR/candidate_run.stdout"
fi
printf 'PASS: macro alias type equality (expected %s)\n' "$expected"
