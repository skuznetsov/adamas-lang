#!/usr/bin/env bash
# Expanded module definitions retain their source arenas through extension.
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
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generated-module-lookup.XXXXXX")"
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
module GeneratedLookupSource
  {% for type in [Int32, Int64] %}
    private def range_value(value : {{type}}) : {{type}}
      value + 1
    end
    def public_value(value : {{type}}) : {{type}}
      value + 2
    end
  {% end %}
  def narrow(value : Int32) : Int32
    range_value(value)
  end
  def wide(value : Int64) : Int64
    range_value(value)
  end
end
module GeneratedLookupConsumer
  extend GeneratedLookupSource
  extend self
end
module GeneratedSelfSource
  extend self
  {% for type in [Int32, Int64] %}
    def generated(value : {{type}}) : {{type}}
      value + 2
    end
  {% end %}
end
module GeneratedSelfConsumer
  extend GeneratedSelfSource
  extend self
end
C.exit(1) unless GeneratedLookupConsumer.narrow(41) == 42
C.putchar(80)
C.exit(2) unless GeneratedLookupConsumer.wide(41_i64) == 42_i64
C.putchar(81)
C.exit(3) unless GeneratedLookupConsumer.public_value(41) == 43
C.putchar(82)
C.exit(4) unless GeneratedLookupConsumer.public_value(41_i64) == 43_i64
C.putchar(83)
C.exit(5) unless GeneratedSelfConsumer.generated(41) == 43
C.putchar(84)
C.exit(6) unless GeneratedSelfConsumer.generated(41_i64) == 43_i64
C.putchar(85)
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
  [[ "$(cat "$WORK_DIR/$producer.out")" == PQRSTU ]] || {
    cat "$WORK_DIR/$producer.out" >&2
    exit 1
  }
done
cmp "$WORK_DIR/original.out" "$WORK_DIR/candidate.out"
echo 'PASS: private and public generated module overloads match Crystal'
