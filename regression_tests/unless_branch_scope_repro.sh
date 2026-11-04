#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT/scripts/run_safe.sh"
ADAMAS="${ADAMAS_BIN:-$ROOT/bin/adamas}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-unless-branch-scope.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

export CRYSTAL_CACHE_DIR="$WORK/cache"
unset ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO

cat >"$WORK/template.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Accept(T)
  def consume(value : T)
    value
  end
end

class IntConsumer
  include Accept(Int32)
end

class Runner
  def initialize(@skip : Bool)
  end

  def run(&) : Nil
    yield
    value = 0
    unless CONDITION
      IntConsumer.new.consume(THEN_ARG)
    else
      IntConsumer.new.consume(ELSE_ARG)
    end
    nil
  end
end

class AnotherRunner
  def run(&) : Nil
    yield
  end
end

def exercise(runner : Runner | AnotherRunner)
  seen = 0
  runner.run do
    seen = 1
  end
  seen
end

LibC.exit(exercise(Runner.new(false)) == 1 &&
          exercise(Runner.new(true)) == 1 &&
          exercise(AnotherRunner.new) == 1 ? 0 : 1)
CR

compile() {
  local mode="$1" source="$2" output="$3"
  if [[ "$mode" == stock ]]; then
    "$SAFE" "$CRYSTAL" 20 2048 build --prelude=empty --no-debug "$source" -o "$output"
  else
    local eager=0
    if [[ "$mode" == eager ]]; then eager=1; fi
    ADAMAS_EAGER_HIR="$eager" "$SAFE" "$ADAMAS" 20 2048 \
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache "$source" -o "$output"
  fi
}

for mode in stock lazy eager; do
  for form in dynamic static_false static_true; do
    case "$form" in
      dynamic) condition='@skip'; invalid_arms=(then else) ;;
      static_false) condition='value.is_a?(Bool)'; invalid_arms=(then) ;;
      static_true) condition='value.is_a?(Int32)'; invalid_arms=(else) ;;
    esac
    sed -e "s/CONDITION/$condition/" -e 's/THEN_ARG/0/' -e 's/ELSE_ARG/1/' \
      "$WORK/template.cr" >"$WORK/valid.cr"
    if ! compile "$mode" "$WORK/valid.cr" "$WORK/valid" >"$WORK/compile.log" 2>&1; then
      cat "$WORK/compile.log" >&2
      exit 1
    fi
    if ! "$SAFE" "$WORK/valid" 5 512 >"$WORK/run.log" 2>&1; then
      cat "$WORK/run.log" >&2
      exit 1
    fi

    for arm in "${invalid_arms[@]}"; do
      then_arg=0
      else_arg=1
      if [[ "$arm" == then ]]; then then_arg=false; else else_arg=false; fi
      sed -e "s/CONDITION/$condition/" -e "s/THEN_ARG/$then_arg/" -e "s/ELSE_ARG/$else_arg/" \
        "$WORK/template.cr" >"$WORK/invalid.cr"
      rc=0
      compile "$mode" "$WORK/invalid.cr" "$WORK/invalid" >"$WORK/invalid.log" 2>&1 || rc=$?
      if [[ "$rc" != 1 ]] ||
         ! grep -Eq 'IntConsumer#consume.*Int32, not Bool|incompatible explicit arguments for concrete generic receiver IntConsumer#consume' "$WORK/invalid.log" ||
         grep -q 'lost its owned' "$WORK/invalid.log"; then
        cat "$WORK/invalid.log" >&2
        exit 1
      fi
      printf 'PASS unless branch scope (%s, %s, %s)\n' "$mode" "$form" "$arm"
    done
  done
done
