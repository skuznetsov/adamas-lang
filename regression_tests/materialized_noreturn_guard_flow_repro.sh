#!/usr/bin/env bash
# Preserve completed-call NoReturn guard flow and reject selected nullable Hash cases.
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

[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "candidate, original Crystal, SAFE runner, or external stdlib is unavailable" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/materialized-noreturn-flow.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original-guard.cache" "$WORK_DIR/candidate-guard.cache" \
    "$WORK_DIR/original-effects.cache" "$WORK_DIR/candidate-effects.cache"
  for name in returning conditional nil; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/guard.cr" <<'CRYSTAL'
class GuardConsumer
  private def halt_request(message : String)
    raise message
  end
  private def bad_request(message : String)
    halt_request(message)
  end
  private def consume(pattern : String, definition : Hash(String, Int32))
    pattern + ":" + definition["value"].to_s
  end
  def run(flag : Bool)
    pattern = flag ? "ok" : nil
    definition = flag ? {"value" => 7} : nil
    unless pattern && definition
      bad_request("missing")
    end
    consume(pattern, definition)
  end
end
puts GuardConsumer.new.run(true)
CRYSTAL
printf 'ok:7\n' >"$WORK_DIR/guard.expected"

cat >"$WORK_DIR/effects.cr" <<'CRYSTAL'
class EffectControls
  private def fail_string(value : String)
    raise value
  end
  private def fail_string(value : Int32)
    value + 1
  end
  private def wrapper(value : String)
    fail_string(value)
  end
  private def conditional(flag : Bool)
    if flag
      fail_string("missing")
    else
      "returned"
    end
  end
  private def rescuing
    begin
      fail_string("caught")
    rescue
      "rescued"
    end
  end
  private def nil_return
    nil
  end
  private def consume(value : String)
    value
  end
  def guard(flag : Bool)
    value = flag ? "guarded" : nil
    unless value
      wrapper("missing")
    end
    consume(value)
  end
  def controls
    puts fail_string(7)
    puts conditional(false)
    puts rescuing
    puts nil_return.nil?
    puts "continued"
  end
end
subject = EffectControls.new
puts subject.guard(true)
subject.controls
CRYSTAL
printf 'guarded\n8\nreturned\nrescued\ntrue\ncontinued\n' >"$WORK_DIR/effects.expected"

write_negative() {
  local kind="$1"
  case "$kind" in
    returning)
      cat >"$WORK_DIR/$kind.cr" <<CRYSTAL
class NegativeGuard
  private def stop; "returns"; end
  private def consume(value : Hash(String, Int32)); value["key"]; end
  def run(flag : Bool)
    value = flag ? {"key" => 7} : nil
    unless value
      stop
    end
    consume(value)
  end
end
NegativeGuard.new.run(true)
CRYSTAL
      ;;
    conditional)
      cat >"$WORK_DIR/$kind.cr" <<CRYSTAL
class NegativeGuard
  private def stop; if false; raise "missing"; else; "returns"; end; end
  private def consume(value : Hash(String, Int32)); value["key"]; end
  def run(flag : Bool)
    value = flag ? {"key" => 7} : nil
    unless value
      stop
    end
    consume(value)
  end
end
NegativeGuard.new.run(true)
CRYSTAL
      ;;
    nil)
      cat >"$WORK_DIR/$kind.cr" <<CRYSTAL
class NegativeGuard
  private def stop; nil; end
  private def consume(value : Hash(String, Int32)); value["key"]; end
  def run(flag : Bool)
    value = flag ? {"key" => 7} : nil
    unless value
      stop
    end
    consume(value)
  end
end
NegativeGuard.new.run(true)
CRYSTAL
      ;;
    *)
      echo "unknown negative case: $kind" >&2
      return 2
      ;;
  esac
}

compile_and_run_positive() {
  local name="$1" compiler="$2" mode="$3" status=0
  local source="$WORK_DIR/$name.cr" output="$WORK_DIR/$mode-$name.bin"
  local log="$WORK_DIR/$mode-$name.compile.log"
  local cache="$WORK_DIR/$mode-$name.cache"
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
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
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
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$mode-$name.run.log" || {
    cat "$WORK_DIR/$mode-$name.run.log" >&2
    return 1
  }
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$mode-$name.stdout"
}

reject_negative() {
  local kind="$1" mode="$2" compiler="$3" status=0
  local source="$WORK_DIR/$kind.cr" log="$WORK_DIR/$mode-$kind.compile.log"
  local cache="$WORK_DIR/$mode-$kind.cache"
  if [[ "$mode" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$kind.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$source" --no-debug \
      --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK_DIR/$mode-$kind.bin" \
      >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
    if [[ "$status" -eq 0 ]] || ! grep -Fq "expected argument #1 to 'NegativeGuard#consume' to be Hash(String, Int32), not (Hash(String, Int32) | Nil)" "$log"; then
      echo "FAIL[$mode/$kind]: expected Crystal's nullable argument type diagnostic" >&2
      cat "$log" >&2
      return 1
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$kind.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-ast-cache --no-llvm-cache \
      --no-debug -o "$WORK_DIR/$mode-$kind.bin" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
    if [[ "$status" -eq 0 ]] || ! grep -Eiq 'no overload matches .*NegativeGuard#consume: expected argument restriction Hash\(String, Int32\), got .*Nil.*Hash\(String, Int32\)' "$log"; then
      echo "FAIL[$mode/$kind]: expected concrete nullable overload/type diagnostic, not a crash" >&2
      cat "$log" >&2
      return 1
    fi
  fi
}

for name in guard effects; do
  if [[ "$name" == guard ]]; then
    write_source="$WORK_DIR/guard.cr"
  else
    write_source="$WORK_DIR/effects.cr"
  fi
  compile_and_run_positive "$name" "$ORIGINAL_CRYSTAL_BIN" original
  compile_and_run_positive "$name" "$COMPILER" candidate
  echo "PASS[$name]: original and candidate output agree"
done

for kind in returning conditional nil; do
  write_negative "$kind"
  reject_negative "$kind" original "$ORIGINAL_CRYSTAL_BIN"
  reject_negative "$kind" candidate "$COMPILER"
  echo "PASS[$kind]: both compilers reject the nullable Hash argument with a type diagnostic"
done

echo "OPEN: rescue-flow Hash and broader CFG adversaries are excluded; current parent and candidate both admit the rescue Hash negative."
