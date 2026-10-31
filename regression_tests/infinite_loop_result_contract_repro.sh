#!/usr/bin/env bash
# Infinite loop results contain break values and no fabricated normal Nil exit.
# Invalid declared returns are covered by declared_method_result_contract_repro.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/infinite-loop-result.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK/cache"
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

for name in return_only break_value nested_break valueless_break mixed_break infinite_tail; do
  cat > "$WORK/$name.cr" <<'CR'
@[Link("c")]
lib InfiniteLoopOutput
  fun putchar(value : Int32) : Int32
end
# The empty prelude does not provide Kernel#loop to the stock compiler.
# Supply its unchanged body so both compilers see a complete source program.
def loop(&)
  while true
    yield
  end
end
CR
  case "$name" in
    return_only)
      cat >> "$WORK/$name.cr" <<'CR'
def loop_result(flag : Bool) : Int32
  loop do
    return 65 if flag
  end
end
InfiniteLoopOutput.putchar(loop_result(true))
CR
      ;;
    break_value)
      cat >> "$WORK/$name.cr" <<'CR'
def loop_result : Int32
  loop do
    break 65
  end
end
InfiniteLoopOutput.putchar(loop_result)
CR
      ;;
    nested_break)
      cat >> "$WORK/$name.cr" <<'CR'
def loop_result : Int32
  loop do
    inner = loop do
      break 65
    end
    break inner
  end
end
InfiniteLoopOutput.putchar(loop_result)
CR
      ;;
    valueless_break)
      cat >> "$WORK/$name.cr" <<'CR'
def loop_result : Nil
  loop do
    break
  end
end
def observe(value : Nil) : Int32; 65; end
InfiniteLoopOutput.putchar(observe(loop_result))
CR
      ;;
    mixed_break)
      cat >> "$WORK/$name.cr" <<'CR'
def loop_result(flag : Bool) : Int32 | Nil
  loop do
    break 65 if flag
    break
  end
end
def observe(value : Int32) : Int32; value; end
def observe(value : Nil) : Int32; 66; end
InfiniteLoopOutput.putchar(observe(loop_result(true)))
InfiniteLoopOutput.putchar(observe(loop_result(false)))
CR
      ;;
    infinite_tail)
      cat >> "$WORK/$name.cr" <<'CR'
def loop_result(flag : Bool) : Int32
  return 65 if flag
  loop do
    next
  end
end
InfiniteLoopOutput.putchar(loop_result(true))
CR
      ;;
  esac
  printf 'InfiniteLoopOutput.putchar(10)\n' >> "$WORK/$name.cr"
  stages=(original lazy eager)
  [[ "${ORIGINAL_ONLY:-0}" == 1 ]] && stages=(original)
  for stage in "${stages[@]}"; do
    log="$WORK/$stage-$name.compile.log"
    binary="$WORK/$stage-$name"
    status=0
    if [[ "$stage" == original ]]; then
      env -u ADAMAS_EAGER_MONO -u ADAMAS_EAGER_HIR \
        CRYSTAL_PATH="$STDLIB" CRYSTAL_CACHE_DIR="$WORK/cache" \
        "$SAFE" "$ORIGINAL" 120 4096 build --prelude=empty --no-debug \
        "$WORK/$name.cr" -o "$binary" > "$log" 2>&1 || status=$?
    else
      mode=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
      [[ "$stage" == eager ]] && mode=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
      "${mode[@]}" CRYSTAL_PATH="$STDLIB" ADAMAS_LLVM_CACHE=0 \
        "$SAFE" "$CANDIDATE" 120 4096 --no-prelude --no-ast-cache --no-llvm-cache \
        "$WORK/$name.cr" -o "$binary" > "$log" 2>&1 || status=$?
    fi
    if [[ "$status" != 0 ]] || ! rg -q '^\[EXIT: 0\]' "$log"; then
      cat "$log" >&2
      echo "FAIL $stage/$name: compile" >&2
      exit 1
    fi
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$binary" 5 512 \
      > "$WORK/$stage-$name.stdout" 2> "$WORK/$stage-$name.run.log" || {
      cat "$WORK/$stage-$name.run.log" >&2
      exit 1
    }
    expected=A
    [[ "$name" == mixed_break ]] && expected=AB
    printf '%s\n' "$expected" > "$WORK/$name.expected"
    diff -u "$WORK/$name.expected" "$WORK/$stage-$name.stdout"
    if [[ "$stage" != original ]]; then
      diff -u "$WORK/original-$name.stdout" "$WORK/$stage-$name.stdout"
    fi
    echo "PASS $stage/$name: $expected"
  done
done
