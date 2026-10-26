#!/usr/bin/env bash
# Crystal instantiates a def only for the argument types that reach it. An
# untyped module class method such as `Crystal::System::File.exists?(path)`
# forwarding `path` to a private `accessible?(path, flag)` was also lowered as
# an unsuffixed base body: the return-type demand on the base name reached
# lower_module_method with no callsite types, which bound `path` to a
# placeholder and materialized `accessible?$Int32_Int32`. Every prelude
# program failed with "undefined method 'check_no_null_byte' for Int32"
# (crystal/system/unix/file.cr:99). Class owners already deferred such bodies
# in lower_method; module owners now do the same. A default-valued parameter
# still types the body, and a method the argument lacks stays rejected.
# Positive cases exit 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/untyped-module-base-defer.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

write_case() {
  local name="$1" kind="$2" visibility="$3" inner="$4" main="$5"
  cat > "$WORK_DIR/$name.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Str
  def nb : Int32
    20
  end
end

module Sys
  $kind Fl
    def self.exists?(path)
      accessible?(path, 22)
    end

    def self.size_or(path, extra = 2)
      path.nb &+ extra
    end

    $visibility def self.accessible?(path, flag)
      $inner
    end
  end
end

class Fl
  def self.exists?(path : Str) : Int32
    Sys::Fl.exists?(path)
  end
end

struct CS
  def self.locate
    Fl.exists?(Str.new)
  end
end

$main
CR
}

# Shape of File.exists? -> Crystal::System::File.exists? -> accessible?.
write_case module_private_forward module private 'path.nb &+ flag' 'LibC.exit(CS.locate)'
write_case module_public_forward module "" 'path.nb &+ flag' 'LibC.exit(CS.locate)'
write_case module_direct_call module private 'path.nb &+ flag' 'LibC.exit(Sys::Fl.exists?(Str.new))'
write_case module_default_param module private 'path.nb &+ flag' 'LibC.exit(Sys::Fl.size_or(Str.new, 22))'
# Control: a class owner already deferred the untyped base body.
write_case class_private_forward class private 'path.nb &+ flag' 'LibC.exit(CS.locate)'
# Negative: Str has no `missing`.
write_case missing_method_rejected module private 'path.missing &+ flag' 'LibC.exit(CS.locate)'

POSITIVE=(module_private_forward module_public_forward module_direct_call module_default_param class_private_forward)
NEGATIVE=(missing_method_rejected)

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
