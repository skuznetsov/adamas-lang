#!/usr/bin/env bash
# Positional defaults and an empty keyword-rest slot retain their call ABI.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/Users/sergey/Projects/Crystal/crystal/src}"
[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/default-double-splat.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
def default_slot_runtime(seed : Int32, file = "default", line = 7, **options) : Int32
  seed + line
end
puts default_slot_runtime(35)
puts default_slot_runtime(35, line: 9)
def dependent_slot_runtime(seed : Int32, first = seed + 1, second = first + 1, **options) : Int32
  seed + second
end
puts dependent_slot_runtime(20)
class ProbeQueue
  def get(*, no_ack = true) : Int32
    no_ack ? 7 : 42
  end
end
class ProbeChannel
  def queue(name)
    ProbeQueue.new
  end
end
class ProbeServer
  def channel
    ProbeChannel.new
  end
end
class ProbeHTTP
  def get(path, headers = nil) : Int32
    1
  end
end
def with_probe_server(&)
  yield ProbeServer.new
end
def serve_probe_metrics(server, &)
  yield ProbeHTTP.new
end
def with_probe_metrics(file = __FILE__, line = __LINE__, &)
  with_probe_server do |s|
    serve_probe_metrics(s) do |http|
      yield({http, s})
    end
  end
end
def with_probe_channel(s : ProbeServer, file = __FILE__, line = __LINE__, **args, &)
  ch = s.channel
  yield ch
end
with_probe_metrics do |http, s|
  with_probe_channel(s) do |ch|
    q = ch.queue("test")
    http.get("/metrics")
    puts q.get(no_ack: false)
  end
end
CRYSTAL

cat >"$WORK_DIR/expected" <<'OUTPUT'
42
44
42
42
OUTPUT

compile_and_run() {
  local producer="$1"
  local compiler="$2"
  shift 2
  local bin="$WORK_DIR/$producer.bin"
  local cache_dir="$WORK_DIR/$producer.cache"
  local compile_log="$WORK_DIR/$producer.compile.log"
  local run_log="$WORK_DIR/$producer.run.log"
  local stdout="$WORK_DIR/$producer.stdout"
  local status=0

  mkdir -p "$cache_dir"
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$WORK_DIR/probe.cr" \
      -o "$bin" --link-flags=-fuse-ld=/usr/bin/ld >"$compile_log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache_dir" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$WORK_DIR/probe.cr" \
      --no-prelude --no-ast-cache --no-llvm-cache -o "$bin" >"$compile_log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]]; then
    cat "$compile_log" >&2
    return "$status"
  fi

  status=0
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$producer.run.resources" \
    "$SAFE_RUNNER" "$bin" 15 512 >"$run_log" 2>&1 || status=$?
  if [[ "$status" != 0 ]] || ! grep -Fq '[EXIT: 0]' "$run_log"; then
    cat "$run_log" >&2
    return 1
  fi
  awk '
    $0 == "=== STDOUT ===" { in_stdout = 1; found = 1; next }
    $0 == "=== STDERR ===" { in_stdout = 0; done = 1; next }
    in_stdout { print }
    END { if (!found || !done) exit 2 }
  ' "$run_log" >"$stdout"
  diff -u "$WORK_DIR/expected" "$stdout"
}

compile_and_run original "$ORIGINAL_CRYSTAL_BIN"
compile_and_run candidate "$COMPILER"
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"
printf 'PASS: defaults and empty keyword-rest preserve direct and nested callback calls\n'
