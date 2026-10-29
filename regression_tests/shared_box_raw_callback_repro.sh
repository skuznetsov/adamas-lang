#!/usr/bin/env bash
# Heap Procs and raw yield callbacks must share the same captured box.
# Qualify every expected exit against original Crystal, then check Adamas.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal)}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shared-box-raw-callback.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/common.cr" <<'CR'
@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end
lib LibC
  fun exit(status : Int32) : NoReturn
end
def rep(n : Int32, &)
  i = 0
  while i < n
    yield i
    i &+= 1
  end
end
CR

cases=()
expected=()
add_case() {
  cases+=("$1")
  expected+=("$2")
  cat "$WORK_DIR/common.cr" > "$WORK_DIR/$1.cr"
  cat >> "$WORK_DIR/$1.cr"
}

add_case proc_writes_block_reads 9 <<'CR'
def run : Int32
  x = 1
  writer = -> { x = 9 }
  got = 0
  rep(1) do |i|
    next if i > 5
    writer.call
    got = x
  end
  got
end
LibC.exit(run)
CR

add_case block_writes_proc_reads 9 <<'CR'
def run : Int32
  x = 1
  reader = -> { x }
  got = 0
  rep(1) do |i|
    next if i > 5
    x = 9
    got = reader.call
  end
  got
end
LibC.exit(run)
CR

add_case alternating_writers 10 <<'CR'
def run : Int32
  x = 1
  writer = -> { x = 10 }
  got = 0
  rep(1) do |i|
    next if i > 5
    x = 9
    writer.call
    got = x
  end
  got
end
LibC.exit(run)
CR

add_case post_call_coherence 10 <<'CR'
def run : Int32
  x = 1
  writer = -> { x = 10 }
  rep(1) do |i|
    next if i > 5
    x = 9
    writer.call
  end
  x
end
LibC.exit(run)
CR

add_case recursive_owner 10 <<'CR'
def run(n : Int32) : Int32
  x = n
  writer = -> { x = n &+ 9 }
  got = 0
  rep(1) do |i|
    next if i > 5
    writer.call
    run(0) if n > 0
    got = x
  end
  got
end
LibC.exit(run(1))
CR

add_case recursive_repeated_yield 10 <<'CR'
def run(n : Int32) : Int32
  x = n
  writer = -> { x = n &+ 9 }
  got = 0
  rep(2) do |i|
    next if i > 5
    run(0) if n > 0 && i == 0
    writer.call
    got = x
  end
  got
end
LibC.exit(run(1))
CR

add_case block_parameter_shadow 1 <<'CR'
def run : Int32
  x = 1
  reader = -> { x }
  rep(1) do |x|
    next if x > 5
    x = 9
  end
  reader.call
end
LibC.exit(run)
CR

add_case recursive_scalar_carriers 10 <<'CR'
def run(n : Int32) : Int32
  got = 0
  rep(2) do |i|
    next if i > 5
    run(0) if n > 0 && i == 0
    got = n &+ 9
  end
  got
end
LibC.exit(run(1))
CR

add_case nilable_shared_payload 9 <<'CR'
def run : Int32
  x = nil.as(Int32?)
  writer = -> { x = 9 }
  got = 0
  rep(1) do |i|
    next if i > 5
    writer.call
    if value = x
      got = value
    end
  end
  got
end
LibC.exit(run)
CR

failures=0
for ((i=0; i<${#cases[@]}; i++)); do
  name="${cases[$i]}"
  want="${expected[$i]}"
  for compiler in crystal adamas; do
    binary="$WORK_DIR/$name.$compiler"
    if [[ "$compiler" == crystal ]]; then
      command_args=("$CRYSTAL_BIN" 120 2048 build "$WORK_DIR/$name.cr" --prelude=empty -o "$binary")
    else
      command_args=("$ADAMAS_BIN" 120 2048 "$WORK_DIR/$name.cr" --prelude=empty -o "$binary")
    fi
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$SAFE" "${command_args[@]}" > "$binary.build.log" 2>&1; then
      printf 'FAIL %s %s: compilation\n' "$name" "$compiler" >&2
      tail -n 20 "$binary.build.log" >&2
      failures=$((failures + 1))
      continue
    fi
    "$SAFE" "$binary" 5 256 > "$binary.run.log" 2>&1 || true
    if ! grep -q "^\[EXIT: $want\]" "$binary.run.log"; then
      printf 'FAIL %s %s: expected exit %s\n' "$name" "$compiler" "$want" >&2
      cat "$binary.run.log" >&2
      failures=$((failures + 1))
    else
      printf 'PASS %s %s exit=%s\n' "$name" "$compiler" "$want"
    fi
  done
done
[[ "$failures" -eq 0 ]]
