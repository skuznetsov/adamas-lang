#!/usr/bin/env bash
# An explicit `def self.new(name : String? = nil, &proc : ->)` that forwards
# `new(name, stack, &proc)` to `initialize(@name, @stack, &@proc)` owns a
# named call such as `F.new(name: "w") { }`. The outer `name:` label binds
# the explicit def, not the initializer. The base allocator generated for
# that call nevertheless applied the label to the positional initializer
# types, missed the block initializer, and fell back to the last same-arity
# overload `initialize(stack : Void*, thread)`, materializing its body under
# the block initializer's name. Every prelude program failed in fiber.cr with
# "undefined method 'gc_thread_handler=' for Fiber::Stack" (Fiber.new from
# Crystal::Scheduler passes `name:` and `&->proc`). The `{% begin %}` wrapper
# mirrors fiber.cr. A label the explicit def does not declare stays rejected.
# Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/explicit-new-named-block.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" body="$2"
  cat > "$WORK_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

# No prelude: a block passed as \`&->m\` is invoked through Proc#call.
struct Proc(*T, R)
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end

class Stk
end

class Th
  @h = 0

  def h=(@h : Int32)
  end

  def h
    @h
  end
end

class F
  @v = 0

  {% begin %}
  def self.new(name : String? = nil, &proc : ->)
    stack = Stk.new
    new(name, stack, &proc)
  end

  def initialize(@name : String?, @stack : Stk, &@proc : ->)
    @v = 1
  end
  {% end %}

  def initialize(stack : Void*, thread)
    thread.h = 40
    @stack = Stk.new
    @proc = -> { }
    @name = "main"
  end

  def v
    @v
  end
end

def go
end

class Sch
  def go
  end

  def run
    F.new(name: "w", &->go)
  end
end

t = Th.new
$body
z = 0
F.new(pointerof(z).as(Void*), t)
LibC.exit(t.h &+ f.v &+ 1)
CR
}

write_case named_block 'f = F.new(name: "w") { }'
write_case named_block_pass 'f = F.new(name: "w", &->go)'
# Shape of Crystal::Scheduler#spawn_stack_pool_collector.
write_case named_block_pass_in_method 'f = Sch.new.run'
# Controls: positional and defaulted calls already worked.
write_case positional_block 'f = F.new("w") { }'
write_case default_block 'f = F.new { }'
# Negative: the explicit def declares no \`nme\` parameter.
write_case unknown_label_rejected 'f = F.new(nme: "w") { }'

POSITIVE=(named_block named_block_pass named_block_pass_in_method positional_block default_block)
NEGATIVE=(unknown_label_rejected)

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${POSITIVE[@]}"; do
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "42" ]]; then
      printf 'ORACLE FAIL: original %s did not exit 42\n' "$name" >&2
      exit 2
    fi
  done
  for name in "${NEGATIVE[@]}"; do
    if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original accepts %s\n' "$name" >&2
      exit 2
    fi
  done
fi

failures=0

for name in "${POSITIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run exit %s)\n' "$name" "$(exit_code_of "$run_log")"
    failures=$((failures + 1))
  fi
done

for name in "${NEGATIVE[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" == "0" ]]; then
    printf 'FAIL %s (accepted)\n' "$name"
    failures=$((failures + 1))
  else
    printf 'PASS %s (rejected)\n' "$name"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$failures" >&2
  exit 1
fi
