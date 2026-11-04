#!/usr/bin/env bash
# Reopened overloads in separate source files must lower from the selected
# method Def's declaration arena, not a sibling's bare-name arena hint.
# Macro-generated Defs use the coordinates of their own expansion buffer.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/method-source-arena.XXXXXX")"
ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
cleanup() {
  local status=$?
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL" ]] || exit 2

cat >"$WORK/initial_method.cr" <<'CRYSTAL'
class MethodSourceArenaOwner
  def value(input : Bool) : Int32
    66
  end
end
CRYSTAL

cat >"$WORK/selected_overload.cr" <<'CRYSTAL'
require "./initial_method"

class MethodSourceArenaOwner
  def value(input : Int32) : Int32
    65
  end
end

@[Link("c")]
lib MethodSourceArenaOutput
  fun putchar(value : Int32) : Int32
end

owner = MethodSourceArenaOwner.new
MethodSourceArenaOutput.putchar(owner.value(1))
MethodSourceArenaOutput.putchar(10)
CRYSTAL

cat >"$WORK/stats.cr" <<'CRYSTAL'
module Stats
  macro define_stats(keys, value)
    def stats
      {
        {% for key in keys %}
          {{key.id}}: {value: {{value}}, rate: 0.0},
        {% end %}
      }
    end
  end
end
CRYSTAL

cat >"$WORK/generated_stats.cr" <<'CRYSTAL'
require "./stats"
require "named_tuple"

@[Link("gc")]
lib LibC
  fun putchar(value : Int32) : Int32
end

abstract class Source
  abstract def details
end

abstract class Counters < Source
  include Stats
  define_stats({"ingress", "egress", "total", "accepted", "rejected", "requeued"}, 65)

  def details
    {code: stats[:ingress][:value], counters: stats}
  end
end

class First < Counters
end

class Second < Counters
  include Stats
  define_stats({"ingress", "egress", "total", "accepted", "rejected", "requeued"}, 66)

  def details
    super.merge(code: stats[:egress][:value])
  end
end

def choose(first : Bool) : Source
  first ? First.new : Second.new
end

def show(source : Source)
  LibC.putchar(source.details[:code])
end

show(choose(true))
show(choose(false))
LibC.putchar(10)
CRYSTAL

printf 'A\n' >"$WORK/selected_overload.expected"
printf 'AB\n' >"$WORK/generated_stats.expected"

compile_case() {
  local mode="$1" source="$2" result="$3" status=0
  local -a command_args mode_env
  mode_env=(env)
  if [[ "$mode" == original ]]; then
    command_args=("$ORIGINAL" 120 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    command_args=("$COMPILER" 120 4096 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    if [[ "$mode" == eager ]]; then
      mode_env+=(ADAMAS_EAGER_MONO=1)
    else
      mode_env+=(-u ADAMAS_EAGER_MONO)
    fi
  fi
  mode_env+=(ADAMAS_LLVM_CACHE=0)
  CRYSTAL_CACHE_DIR="$WORK/cache.$mode" "${mode_env[@]}" \
    "$SAFE_RUNNER" "${command_args[@]}" "$WORK/$source.cr" -o "$WORK/$result.bin" \
    >"$WORK/$result.compile.log" 2>&1 || status=$?
  return "$status"
}

run_case() {
  local mode="$1" source="$2"
  local result="$source.$mode"
  if ! compile_case "$mode" "$source" "$result"; then
    cat "$WORK/$result.compile.log" >&2
    return 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK/$result.bin" 5 512 \
    >"$WORK/$result.stdout" 2>"$WORK/$result.run.log" || {
      cat "$WORK/$result.run.log" >&2
      return 1
    }
  diff -u "$WORK/$source.expected" "$WORK/$result.stdout"
  echo "PASS[$mode]: $source"
}

for mode in original lazy eager; do
  run_case "$mode" selected_overload
  run_case "$mode" generated_stats
done
