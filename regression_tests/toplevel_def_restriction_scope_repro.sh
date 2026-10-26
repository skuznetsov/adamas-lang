#!/usr/bin/env bash
# Overload matching resolved a top-level def's restrictions in the caller's
# class. Inside OptionParser, which nests `class Exception < ::Exception`,
# `raise ArgumentError.new(...)` checked `raise(exception : Exception)`
# against OptionParser::Exception and failed with "no overload matches raise
# for argument types (ArgumentError)", stopping stage 2. A top-level def's
# restrictions resolve in the program scope; an owned def keeps its owner's
# scope. Each case exits 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/toplevel-restriction-scope.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Exception
  def initialize(@code : Int32)
  end

  def code : Int32
    @code
  end
end

class ArgumentError < Exception
end

def boom(exception : Exception) : Int32
  exception.code
end
CR

cat > "$WORK_DIR/class_caller.cr" <<'CR'
class Par
  class Exception < ::Exception
  end

  def check : Int32
    boom ArgumentError.new(42)
  end
end

LibC.exit(Par.new.check)
CR

cat > "$WORK_DIR/module_self_caller.cr" <<'CR'
module Nest
  class Exception < ::Exception
  end

  def self.check : Int32
    boom(ArgumentError.new(42))
  end
end

LibC.exit(Nest.check)
CR

cat > "$WORK_DIR/included_module_caller.cr" <<'CR'
module Mo
  class Exception < ::Exception
  end

  def check : Int32
    boom(ArgumentError.new(42))
  end
end

class K
  include Mo

  def initialize
  end
end

LibC.exit(K.new.check)
CR

# A def owned by Par still sees Par::Exception.
cat > "$WORK_DIR/owner_scope_kept.cr" <<'CR'
class Par
  class Exception < ::Exception
  end

  def own(exception : Exception) : Int32
    exception.code
  end

  def check : Int32
    own(Par::Exception.new(42))
  end
end

LibC.exit(Par.new.check)
CR

CASES=(
  "class_caller:42"
  "module_self_caller:42"
  "included_module_caller:42"
  "owner_scope_kept:42"
)

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  cat "$WORK_DIR/header.cr" "$WORK_DIR/$name.cr" > "$WORK_DIR/$name.full.cr"
  mv "$WORK_DIR/$name.full.cr" "$WORK_DIR/$name.cr"
done

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
fi

failures=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
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
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d top-level restriction scope case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'top-level restriction scope cases passed\n'
