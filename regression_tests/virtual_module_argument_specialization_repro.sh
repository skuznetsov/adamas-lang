#!/usr/bin/env bash
# Concrete callsite arguments must specialize an implementation inherited from
# a module restriction before its body resolves narrower nested calls.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-180}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
ONLY_CASES="${ONLY_CASES:-all}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/virtual-module-argument-specialization.XXXXXX")"

cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 || "${KEEP_ARTIFACTS:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ "$ORIGINAL_ONLY" != "0" && "$ORIGINAL_ONLY" != "1" ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -d "$CRYSTAL_STDLIB" ]]; then
  echo "ERROR: safe runner, installed Crystal, or Crystal stdlib is unavailable" >&2
  echo "Usage: ORIGINAL_ONLY=1 ONLY_CASES=all ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != "1" && ! -x "$ADAMAS_BIN" ]]; then
  echo "ERROR: candidate compiler is unavailable" >&2
  echo "Usage: ADAMAS_BIN=/path/to/adamas ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0" >&2
  exit 2
fi

ALL_CASES=(virtual_arguments descriptor_only_rejection named_block_dispatch named_block_argument named_block_argument_rejection)
if [[ "$ONLY_CASES" == "all" ]]; then
  SELECTED_CASES=("${ALL_CASES[@]}")
else
  normalized_cases="${ONLY_CASES//,/ }"
  read -r -a SELECTED_CASES <<<"$normalized_cases"
  if [[ "${#SELECTED_CASES[@]}" -eq 0 ]]; then
    echo "ERROR: ONLY_CASES must be all or a comma/space-separated case list" >&2
    exit 2
  fi
  for selected in "${SELECTED_CASES[@]}"; do
    known=0
    for available in "${ALL_CASES[@]}"; do
      [[ "$selected" == "$available" ]] && known=1
    done
    if [[ "$known" != "1" ]]; then
      printf 'ERROR: unknown ONLY_CASES entry: %s\nAvailable: %s\n' \
        "$selected" "${ALL_CASES[*]}" >&2
      exit 2
    fi
  done
fi

write_source() {
  local name="$1"
  local path="$WORK_DIR/$name.cr"
  if [[ "$name" == "named_block_dispatch" ]]; then
    cp "$ROOT_DIR/regression_tests/fixtures/virtual_named_block_dispatch.cr" "$path"
    return
  fi
  cat >"$path" <<'CRYSTAL'
@[Link("c")]
lib VirtualModuleOutput
  fun putchar(value : Int32) : Int32
end

module VirtualDescriptor
end

class VirtualIO
end

class VirtualFD < VirtualIO
  include VirtualDescriptor
end

class VirtualSocket < VirtualIO
  include VirtualDescriptor
end

class VirtualNotIO
  include VirtualDescriptor
end

module VirtualLoop
  abstract def read(io : VirtualDescriptor) : Int32
end

class VirtualPoller
  include VirtualLoop

  def read(io : VirtualDescriptor) : Int32
    check_open(io)
  end

  def check_open(io : VirtualIO) : Int32
    65
  end
end

class VirtualInheritedPoller < VirtualPoller
end

def selected : VirtualLoop
  VirtualPoller.new
end

def selected_inherited : VirtualLoop
  VirtualInheritedPoller.new
end

CRYSTAL

  if [[ "$name" == named_block_argument* ]]; then
    cat >>"$path" <<'CRYSTAL'
require "primitives"

module VirtualLoop
  abstract def read(*, io : VirtualDescriptor, enabled : Bool, &block : ->) : Int32
end

class VirtualPoller
  def read(*, io : VirtualDescriptor, enabled : Bool, &block : ->) : Int32
    block.call
    enabled ? check_open(io) : 0
  end
end

def forward(reader : VirtualLoop, io, enabled = true, &block)
  reader.read(io: io, enabled: enabled, &block)
end
CRYSTAL
  fi
  case "$name" in
    named_block_argument)
      cat >>"$path" <<'CRYSTAL'
VirtualModuleOutput.putchar(forward(selected, VirtualFD.new) { nil })
VirtualModuleOutput.putchar(forward(selected_inherited, VirtualSocket.new) { nil })
VirtualModuleOutput.putchar(10)
CRYSTAL
      ;;
    named_block_argument_rejection)
      cat >>"$path" <<'CRYSTAL'
VirtualModuleOutput.putchar(forward(selected, VirtualNotIO.new) { nil })
CRYSTAL
      ;;
    virtual_arguments)
      cat >>"$path" <<'CRYSTAL'
VirtualModuleOutput.putchar(selected.read(VirtualFD.new))
VirtualModuleOutput.putchar(selected.read(VirtualSocket.new))
VirtualModuleOutput.putchar(selected_inherited.read(VirtualFD.new))
VirtualModuleOutput.putchar(selected_inherited.read(VirtualSocket.new))
VirtualModuleOutput.putchar(10)
CRYSTAL
      ;;
    descriptor_only_rejection)
      cat >>"$path" <<'CRYSTAL'
VirtualModuleOutput.putchar(selected.read(VirtualNotIO.new))
VirtualModuleOutput.putchar(10)
CRYSTAL
      ;;
    *)
      printf 'ERROR: no source writer for case %s\n' "$name" >&2
      return 2
      ;;
  esac
}

compile_one() {
  local stage="$1" name="$2"
  local source="$WORK_DIR/$name.cr"
  local binary="$WORK_DIR/$stage-$name.bin"
  local log="$WORK_DIR/$stage-$name.build.log"
  local cache="$WORK_DIR/$stage-$name.cache"
  local rc=0
  local -a mode_env
  mkdir -p "$cache"

  if [[ "$stage" == "original" ]]; then
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" build --prelude=empty --no-debug "$source" \
      -o "$binary" --link-flags=-fuse-ld=/usr/bin/ld >"$log" 2>&1 || rc=$?
  else
    if [[ "$stage" == "candidate-eager" ]]; then
      mode_env=(env ADAMAS_EAGER_CLASSVAR_INIT=1)
    else
      mode_env=(env -u ADAMAS_EAGER_CLASSVAR_INIT)
    fi
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      "${mode_env[@]}" "$SAFE_RUNNER" "$ADAMAS_BIN" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" "$source" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1 || rc=$?
  fi

  printf '%s\n' "$rc" >"$WORK_DIR/$stage-$name.build.status"
  printf '%s\n' "$binary"
}

check_positive() {
  local stage="$1" name="$2" expected="$3" binary log stdout rc
  binary="$(compile_one "$stage" "$name")"
  log="$WORK_DIR/$stage-$name.build.log"
  rc="$(cat "$WORK_DIR/$stage-$name.build.status")"
  if [[ "$rc" != "0" ]]; then
    cat "$log" >&2
    printf 'FAIL %s %s: expected successful compile\n' "$stage" "$name" >&2
    return 1
  fi

  log="$WORK_DIR/$stage-$name.run.log"
  stdout="$WORK_DIR/$stage-$name.stdout"
  rc=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.run.resources.json" \
    "$SAFE_RUNNER" "$binary" 10 512 >"$stdout" 2>"$log" || rc=$?
  if [[ "$rc" != "0" ]] || ! rg -Fq '[EXIT: 0]' "$log"; then
    cat "$log" >&2
    cat "$stdout" >&2
    printf 'FAIL %s %s: native run did not exit zero\n' "$stage" "$name" >&2
    return 1
  fi

  printf '%s\n' "$expected" >"$WORK_DIR/$name.expected"
  if ! diff -u "$WORK_DIR/$name.expected" "$stdout"; then
    printf 'FAIL %s %s: output differed from expected output\n' "$stage" "$name" >&2
    return 1
  fi
  if [[ "$stage" != "original" ]] && ! diff -u "$WORK_DIR/original-$name.stdout" "$stdout"; then
    printf 'FAIL %s %s: output differed from original Crystal\n' "$stage" "$name" >&2
    return 1
  fi
  printf 'PASS %s %s output=%q\n' "$stage" "$name" "$expected"
}

check_descriptor_only_rejection() {
  local stage="$1" name="$2" binary log rc
  binary="$(compile_one "$stage" "$name")"
  log="$WORK_DIR/$stage-$name.build.log"
  rc="$(cat "$WORK_DIR/$stage-$name.build.status")"
  if [[ "$rc" != "1" ]] || ! rg -qi 'check_open' "$log" || ! rg -qi 'VirtualNotIO' "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: expected inner VirtualIO restriction rejection\n' "$stage" "$name" >&2
    return 1
  fi
  if rg -qi 'syntax error|parser errors|internal compiler error|unhandled exception|timed out|resource limit' "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: rejection was not a source type-check result\n' "$stage" "$name" >&2
    return 1
  fi
  printf 'PASS %s %s rejected descriptor-only argument at check_open\n' "$stage" "$name"
}

for name in "${SELECTED_CASES[@]}"; do
  write_source "$name"
  if [[ "$name" == *_rejection ]]; then
    check_descriptor_only_rejection original "$name"
    if [[ "$ORIGINAL_ONLY" != "1" ]]; then
      check_descriptor_only_rejection candidate-lazy "$name"
      check_descriptor_only_rejection candidate-eager "$name"
    fi
    continue
  fi

  case "$name" in
    named_block_dispatch) expected=".A.B.C.D.E.F.G.H" ;;
    named_block_argument) expected="AA" ;;
    *) expected="AAAA" ;;
  esac
  check_positive original "$name" "$expected"
  if [[ "$ORIGINAL_ONLY" != "1" ]]; then
    check_positive candidate-lazy "$name" "$expected"
    check_positive candidate-eager "$name" "$expected"
  fi
done

if [[ "$ORIGINAL_ONLY" == "1" ]]; then
  printf 'PASS: original Crystal qualified virtual module argument specialization cases (%s)\n' \
    "${SELECTED_CASES[*]}"
else
  printf 'PASS: virtual module argument specialization matches original Crystal (%s)\n' \
    "${SELECTED_CASES[*]}"
fi
