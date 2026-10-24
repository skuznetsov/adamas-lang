#!/usr/bin/env bash
# A method lowered from its mangled name re-resolved the canonical suffix types
# (and tracked enum names) in the owner's namespace. Inside
# `Crystal::System::Sigset`, the top-level enum `Signal` of `delete$Signal`
# became the module `Crystal::System::Signal`, so prelude hello failed with
# "argument #2 of 'LibC.sigdelset' must be Int32, not Crystal::System::Signal"
# and a plain `signal.to_i32!` reported an undefined method on the module.
# top_level_owner is the control: the same code with a top-level owner.
# nested_type_arg guards a qualified argument type of the same namespace.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/namespaced-owner-enum-arg.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun exit(status : Int32) : NoReturn
  fun abs(Int32) : Int32
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

enum Signal : Int32
  INT = 2

  def to_i32! : Int32
    5
  end

  def reset : Int32
    Crystal::System::Signal.reset(self)
  end
end

module Crystal
  module System
  end
end
CR

write_case() {
  local name="$1" body="$2"
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$body"; } > "$WORK_DIR/$name.cr"
}

write_case extern_arg '
struct Crystal::System::Sigset
  def delete(signal) : Int32
    LibC.abs(signal)
  end
end
LibC.exit(Crystal::System::Sigset.new.delete(Signal::INT))'
write_case method_arg '
struct Crystal::System::Sigset
  def d2(signal) : Int32
    signal.to_i32!
  end
end
module Crystal::System::Signal
end
LibC.exit(Crystal::System::Sigset.new.d2(Signal::INT))'
write_case via_module '
struct Crystal::System::Sigset
  def delete(signal) : Int32
    LibC.abs(signal)
  end
end
module Crystal::System::Signal
  @@sigset = Sigset.new

  def self.reset(signal) : Int32
    @@sigset.delete(signal)
  end
end
LibC.exit(Signal::INT.reset)'
write_case top_level_owner '
struct Sigset
  def d2(signal) : Int32
    signal.to_i32!
  end
end
module Crystal::System::Signal
end
LibC.exit(Sigset.new.d2(Signal::INT))'
write_case nested_type_arg '
struct Crystal::System::Tag
  def id : Int32
    7
  end
end
struct Crystal::System::Sigset
  def d2(tag) : Int32
    tag.id
  end
end
LibC.exit(Crystal::System::Sigset.new.d2(Crystal::System::Tag.new))'

CASES=(extern_arg:5 method_arg:5 via_module:5 top_level_owner:5 nested_type_arg:7)

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
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
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
  printf '%d namespaced-owner enum argument case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'namespaced-owner enum argument cases passed\n'
