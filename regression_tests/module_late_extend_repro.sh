#!/usr/bin/env bash
# Late module reopenings must export retained methods without losing static dispatch.
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
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/late-module-extend.XXXXXX")"
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
module LateSource
end
module LateConsumer
  extend LateSource
  extend self
end
module LateOverride
  extend LateSource
  def self.narrow(value : Int32) : Int32
    value + 100
  end
end
module LateSource
  {% for type in [Int32, Int64] %}
    private def hidden(value : {{type}}) : {{type}}
      value + 1
    end
  {% end %}
  def narrow(value : Int32) : Int32
    hidden(value)
  end
  def wide(value : Int64) : Int64
    hidden(value)
  end
end
module LateNested
  module Source
  end
  module Consumer
    extend Source
    extend self
  end
  module Source
    private def hidden(value : Int32) : Int32
      value + 3
    end
    def value(input : Int32) : Int32
      hidden(input)
    end
  end
end
module LateSelf
  extend self
end
module LateSelf
  {% for type in [Int32] %}
    private def hidden(value : {{type}}) : {{type}}
      value + 4
    end
  {% end %}
  def value(input : Int32) : Int32
    hidden(input)
  end
end
module LexicalSource
end
module LexicalConsumer
  OFFSET = 100
  extend LexicalSource
  extend self
end
module LexicalSource
  OFFSET = 5
  {% for type in [Int32] %}
    private def hidden(value : {{type}}) : {{type}}
      value + OFFSET
    end
  {% end %}
  def value(input : Int32) : Int32
    hidden(input)
  end
end
C.exit(1) unless LateConsumer.narrow(41) == 42
C.putchar(65)
C.exit(2) unless LateConsumer.wide(41_i64) == 42_i64
C.putchar(66)
C.exit(3) unless LateOverride.narrow(41) == 141
C.putchar(67)
C.exit(4) unless LateNested::Consumer.value(41) == 44
C.putchar(68)
C.exit(5) unless LateSelf.value(41) == 45
C.putchar(69)
C.exit(6) unless LexicalConsumer.value(41) == 46
C.putchar(70)
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
  [[ "$(cat "$WORK_DIR/$producer.out")" == ABCDEF ]] || {
    cat "$WORK_DIR/$producer.out" >&2
    exit 1
  }
done
cmp "$WORK_DIR/original.out" "$WORK_DIR/candidate.out"
echo 'PASS: late module exports and lexical/override controls match Crystal'
