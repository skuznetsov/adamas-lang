#!/usr/bin/env bash
# Multiline literal spans must retain classes in their parser-owned namespace arenas.
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
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/multiline-namespace.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/heredoc.cr" <<'CRYSTAL'
module HeredocPosition
  class Child
    def self.banner
      <<-TEXT
      first
      second
      TEXT
    end
    def self.value : Int32
      65
    end
  end
end
CRYSTAL
cat >"$WORK_DIR/percent_string.cr" <<'CRYSTAL'
module PercentStringPosition
  class Child
    def self.banner
      %q{first
second
third}
    end
    def self.value : Int32
      66
    end
  end
end
CRYSTAL
cat >"$WORK_DIR/percent_regex.cr" <<'CRYSTAL'
module PercentRegexPosition
  class Child
    def self.banner
      %r{first
second
third}
    end
    def self.value : Int32
      67
    end
  end
end
CRYSTAL
cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end
require "./heredoc"
require "./percent_string"
require "./percent_regex"
C.putchar(HeredocPosition::Child.value)
C.putchar(PercentStringPosition::Child.value)
C.putchar(PercentRegexPosition::Child.value)
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
  [[ "$(cat "$WORK_DIR/$producer.out")" == ABC ]] || {
    cat "$WORK_DIR/$producer.out" >&2
    exit 1
  }
done
cmp "$WORK_DIR/original.out" "$WORK_DIR/candidate.out"
echo 'PASS: multiline namespace registration matches Crystal'
