#!/usr/bin/env bash
# An inline consumer must wait for the exact results of both selected producers.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--lgc -fuse-ld=/usr/bin/ld}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/force-depth-inline-exact.XXXXXX")"

cleanup() {
  local result=$?
  rm -rf -- "$WORK_DIR"/cache-*
  if [[ "$result" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$ADAMAS_BIN" || ! -x "$ORIGINAL_CRYSTAL_BIN" ||
      ! -x "$SAFE_RUNNER" || ! -f "$CRYSTAL_STDLIB/empty.cr" ]]; then
  echo "ERROR: candidate, original Crystal, safe runner, and stock stdlib are required" >&2
  exit 2
fi

write_source() {
  local owner="$1" prelude="$2" invalid="$3" path="$4"
  local nested="${5:-0}" entry_target=Entry.read producer='Context(T).new(marker)'
  cat >"$path" <<'CRYSTAL'
@[Link("c")]
lib Native
  fun putchar(value : Int32) : Int32
end

class Context(T)
  def initialize(@marker : Int32)
  end
  def marker
    @marker
  end
end

module Action(T)
CRYSTAL
  if [[ "$nested" == 1 ]]; then
    cat >>"$path" <<'CRYSTAL'
  def produce0(marker)
    Context(T).new(marker)
  end
CRYSTAL
    for level in 1 2 3 4 5 6 7; do
      printf '  def produce%s(marker)\n    produce%s(marker)\n  end\n' \
        "$level" "$((level - 1))" >>"$path"
    done
    producer='produce7(marker)'
  fi
  printf '  def create(marker)\n    context = %s\n' "$producer" >>"$path"
  cat >>"$path" <<'CRYSTAL'
    self.wait(context)
    context
  end
  def consume(context : Context)
    88
  end
  def consume(context : Context(T))
    context.marker
  end
end

class Receive(T)
  include Action(T)
  def wait(context : Context(T)) : Nil
  end
end

class Timeout
  include Action(Nil)
  def wait(context : Context(Nil)) : Nil
  end
end

class Actions(A, B)
  def initialize(@first : A, @second : B)
  end
  def each(&)
    yield @first
    yield @second
  end
end
CRYSTAL
  if [[ "$owner" == top-level ]]; then
    echo 'def read_inline(ops, marker)' >>"$path"
    entry_target=entry_read
  else
    printf '\n%s Consumer\n  def self.read(ops, marker)\n' "$owner" >>"$path"
  fi
  cat >>"$path" <<'CRYSTAL'
    offset = marker
    adjust = ->(value : Int32) { value &+ offset }
    mutate = -> { offset &+= 1 }
    total = 0
CRYSTAL
  if [[ "$prelude" == stock ]]; then
    if [[ "$invalid" == 1 ]]; then
      echo '    contexts = ops.map { |op| 33 }' >>"$path"
    else
      echo '    contexts = ops.map { |op| op.create(adjust.call(0)) }' >>"$path"
    fi
    echo '    total = ops[0].consume(contexts[0]) &+ ops[1].consume(contexts[1])' >>"$path"
  else
    echo '    ops.each do |op|' >>"$path"
    if [[ "$invalid" == 1 ]]; then
      echo '      context = 33' >>"$path"
    else
      echo '      context = op.create(adjust.call(0))' >>"$path"
    fi
    echo '      total &+= op.consume(context)' >>"$path"
    echo '    end' >>"$path"
  fi
  cat >>"$path" <<'CRYSTAL'
    mutate.call
    Native.putchar(offset &+ 32)
    total
  end
CRYSTAL
  if [[ "$owner" == top-level ]]; then
    cat >>"$path" <<'CRYSTAL'
def entry_read(ops, marker)
  read_inline(ops, marker)
end
CRYSTAL
  else
    cat >>"$path" <<'CRYSTAL'
end

class Entry
  def self.read(ops, marker)
    Consumer.read(ops, marker)
  end
end
CRYSTAL
  fi
  if [[ "$nested" == 1 ]]; then
    for level in 0 1 2 3 4 5 6 7; do
      printf 'class Wrapper%s\n  def self.read(ops, marker)\n    %s(ops, marker)\n  end\nend\n' \
        "$level" "$entry_target" >>"$path"
      entry_target="Wrapper$level.read"
    done
  fi
  if [[ "$prelude" == stock ]]; then
    printf 'Native.putchar(%s({Receive(Nil).new, Timeout.new}, 33))\n' "$entry_target" >>"$path"
  else
    printf 'Native.putchar(%s(Actions.new(Receive(Nil).new, Timeout.new), 33))\n' "$entry_target" >>"$path"
  fi
  echo 'Native.putchar(10)' >>"$path"
}

check_one() {
  local name="$1" prelude="$2" invalid="$3" mode="$4"
  local log="$WORK_DIR/$name-$mode.build.log" binary="$WORK_DIR/$name-$mode"
  local result=0 compiler="$ADAMAS_BIN"
  local -a args=() mode_env=(-u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
  if [[ "$mode" == original ]]; then
    compiler="$ORIGINAL_CRYSTAL_BIN"
    args=(build --no-debug "$WORK_DIR/$name.cr" -o "$binary" "--link-flags=$LINK_FLAGS")
    [[ "$prelude" == empty ]] && args+=(--prelude=empty)
  else
    args=("$WORK_DIR/$name.cr" --no-debug --no-ast-cache --no-llvm-cache -o "$binary")
    [[ "$prelude" == empty ]] && args+=(--no-prelude)
    [[ "$mode" == eager ]] && mode_env+=(ADAMAS_EAGER_MONO=1)
  fi
  CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/cache-$name-$mode" \
    ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" \
    DEBUG_FORCE_LOWER_DEPTH=1 env "${mode_env[@]}" \
    "$SAFE_RUNNER" "$compiler" "${COMPILE_TIMEOUT_SEC:-180}" \
    "${COMPILE_MAX_MEM_MB:-8192}" "${args[@]}" >"$log" 2>&1 || result=$?
  if [[ "$invalid" == 1 ]]; then
    if [[ "$result" != 1 ]] || ! rg -q 'error:|Error:' "$log" ||
       ! rg -q 'consume' "$log" || [[ -f "$binary" ]]; then
      cat "$log" >&2
      echo "FAIL $name $mode accepted an Int32 context" >&2
      return 1
    fi
    echo "PASS $name $mode rejected Int32 context"
    return
  fi
  if [[ "$result" != 0 ]] || ! rg -q '^\[EXIT: 0\]( |$)' "$log"; then
    cat "$log" >&2
    echo "FAIL $name $mode compilation" >&2
    return 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 \
    >"$WORK_DIR/$name-$mode.stdout" 2>"$WORK_DIR/$name-$mode.run.log"
  printf 'BB\n' >"$WORK_DIR/expected"
  diff -u "$WORK_DIR/expected" "$WORK_DIR/$name-$mode.stdout"
  if [[ "$mode" != original ]]; then
    diff -u "$WORK_DIR/$name-original.stdout" "$WORK_DIR/$name-$mode.stdout"
    # Exercise suspension before strict argument admission, plus a second
    # producer discovered while rebuilding the same captured consumer.
    local consumer_name=Consumer.read
    [[ "$name" == top-level-* ]] && consumer_name=read_inline
    for producer in 'Receive(Nil)' Timeout; do
      for event in SUSPENDED RESUMED; do
        if ! rg -F "[FORCE_LOWER_$event] consumer=$consumer_name\$" "$log" | \
          rg -Fq "producer=$producer#create\$Int32"; then
          cat "$log" >&2
          echo "FAIL $name $mode missing $event for $producer" >&2
          return 1
        fi
      done
    done
  fi
  echo "PASS $name $mode output=BB"
}

for owner in class module top-level; do
  for prelude in empty stock; do
    for invalid in 0 1; do
      name="$owner-$prelude-$invalid"
      write_source "$owner" "$prelude" "$invalid" "$WORK_DIR/$name.cr"
      modes=(original lazy)
      # Whole-prelude eager materialization has a separate Time::Instant
      # baseline failure. Empty-prelude cases qualify both scheduling modes.
      [[ "$prelude" == empty ]] && modes+=(eager)
      for mode in "${modes[@]}"; do
        check_one "$name" "$prelude" "$invalid" "$mode"
      done
    done
  done
done
for prelude in empty stock; do
  name="nested-$prelude-0"
  write_source class "$prelude" 0 "$WORK_DIR/$name.cr" 1
  modes=(original lazy)
  [[ "$prelude" == empty ]] && modes+=(eager)
  for mode in "${modes[@]}"; do
    check_one "$name" "$prelude" 0 "$mode"
  done
done
echo 'PASS inline exact-result replay matches Crystal'
