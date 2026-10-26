#!/usr/bin/env bash
# `::File::Info.new(st)` inside `module Crystal::System::FileDescriptor` names
# the top-level `File::Info`. The `.new` lowering re-resolved the already
# resolved path receiver in the caller's namespace, where `Crystal` also
# declares `DWARF::Info` and a sibling `System::File` module, and allocated
# the wrong type: `system_info.type` silently returned 0 here, and the prelude
# failed with "undefined method 'type' for Crystal::DWARF::Info". A resolved
# path receiver is not re-resolved; a call from a top-level def keeps working;
# an undeclared path stays rejected. Positive cases exit 42 under original
# Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/absolute-path-new.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" main_body="$2"
  cat > "$WORK_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

module Crystal::System::FileInfo
  def initialize(@s : Int32)
  end

  def type
    @s
  end
end

module Crystal
  module DWARF
    struct Info
      @off : Int64

      def initialize(@io : Int32, @off)
      end
    end
  end
end

class File
  struct Info
    include Crystal::System::FileInfo
  end
end

module Crystal::System::File
  def self.info(x)
    ::File::Info.new(x)
  end
end

def top_info(st)
  ::File::Info.new(st)
end

module Crystal::System::FileDescriptor
  def self.system_info(fd)
    st = fd &+ 1
    $main_body
  end

  private def system_info
    FileDescriptor.system_info 41
  end

  def run
    system_info.type
  end
end

class FD
  include Crystal::System::FileDescriptor
end

LibC.exit(FD.new.run)
CR
}

# Shape of Crystal::System::FileDescriptor.system_info (file_descriptor.cr).
write_case absolute_path_in_namespace '::File::Info.new(st)'
# Control: a top-level call needs no namespace walk.
write_case top_level_control 'top_info(st)'
# Negative: no File::Missing is declared.
write_case undeclared_path_rejected '::File::Missing.new(st)'

POSITIVE=(absolute_path_in_namespace top_level_control)
NEGATIVE=(undeclared_path_rejected)

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
