#!/usr/bin/env bash
# Macro-emitted extend self exports included methods after member registration.
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
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-module-self.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib C
  fun exit(status : Int32) : NoReturn
  fun putchar(value : Int32) : Int32
end
module ConditionalSelfSource
  def value(input : Int32) : Int32
    input + 1
  end
end
module ConditionalSelfConsumer
  include ConditionalSelfSource
  {% if false %}
    def self.value(input : Int32) : Int32
      input + 9
    end
  {% else %}
    extend self
  {% end %}
end
module NamedSelfSource
  def value(input : Int32) : Int32
    input + 2
  end
end
module NamedSelfConsumer
  include NamedSelfSource
  macro export_self
    extend self
  end
  export_self
end
module ConditionalSelfNested
  module Source
    def value(input : Int32) : Int32
      input + 3
    end
  end
  module Consumer
    include Source
    {% if true %}
      extend self
    {% end %}
  end
end
module GenericSelfSource(T)
  def value(input : T) : T
    input
  end
end
module GenericSelfConsumer
  include GenericSelfSource(Int64)
  extend self
end
C.exit(1) unless ConditionalSelfConsumer.value(41) == 42
C.putchar(77)
C.exit(2) unless NamedSelfConsumer.value(41) == 43
C.putchar(78)
C.exit(3) unless ConditionalSelfNested::Consumer.value(41) == 44
C.putchar(79)
C.exit(4) unless GenericSelfConsumer.value(41_i64) == 41_i64
C.putchar(71)
CRYSTAL

for producer in original candidate; do
  bin="$WORK_DIR/$producer.bin"
  cache="$WORK_DIR/$producer.cache"
  mkdir -p "$cache"
  status=0
  if [[ "$producer" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/probe.cr" \
      -o "$bin" --link-flags=-fuse-ld=/usr/bin/ld >"$WORK_DIR/$producer.build.log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS=-fuse-ld=/usr/bin/ld \
      "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" --no-prelude \
      --no-ast-cache --no-llvm-cache -o "$bin" >"$WORK_DIR/$producer.build.log" 2>&1 || status=$?
  fi
  if [[ "$status" != 0 ]]; then
    cat "$WORK_DIR/$producer.build.log" >&2
    exit "$status"
  fi
  status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$bin" 15 512 >"$WORK_DIR/$producer.out" 2>"$WORK_DIR/$producer.run.log" || status=$?
  if [[ "$status" != 0 ]]; then
    cat "$WORK_DIR/$producer.run.log" >&2
    exit "$status"
  fi
  [[ "$(cat "$WORK_DIR/$producer.out")" == MNOG ]] || {
    cat "$WORK_DIR/$producer.out" >&2
    exit 1
  }
done
cmp "$WORK_DIR/original.out" "$WORK_DIR/candidate.out"
echo 'PASS: macro-emitted extend self and generic include match Crystal'
