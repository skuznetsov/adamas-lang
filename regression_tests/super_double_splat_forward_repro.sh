#!/usr/bin/env bash
# `super a, **opts` / `super(a, **opts)` must forward the NamedTuple to an
# ancestor `**opts` parameter. The super parser only knew `*`, so `**opts`
# became `opts` squared (paren form: a parse error) and 1.22.1's
# `File::Error.new_from_os_error` (`super message, os_error, **opts`) failed
# with "undefined method 'code' for NamedTuple".
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/super-double-splat.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

struct Int32
  @[Primitive(:binary)]
  def +(other : Int32) : Int32
  end
end

def target(a : Int32, *, b : Int32, c : Int32 = 1) : Int32
  a + b + c
end
CR

write_case() {
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$2"; } > "$WORK_DIR/$1.cr"
}

write_case class_method_command_form '
class P
  def self.run(a : Int32, **opts) : Int32
    target(a, **opts)
  end
end

class K < P
  def self.run(a : Int32, **opts) : Int32
    super a, **opts
  end
end

LibC.exit(K.run(1, c: 30, b: 11))'

write_case class_method_paren_form '
class P
  def self.run(a : Int32, **opts) : Int32
    target(a, **opts)
  end
end

class K < P
  def self.run(a : Int32, **opts) : Int32
    super(a + 1, **opts)
  end
end

LibC.exit(K.run(0, b: 40))'

write_case instance_paren_form '
class P
  def run(a : Int32, **opts) : Int32
    target(a, **opts)
  end
end

class K < P
  def run(a : Int32, **opts) : Int32
    super(a, **opts)
  end
end

LibC.exit(K.new.run(1, b: 40))'

CASES=(class_method_command_form:42 class_method_paren_form:42 instance_paren_form:42)

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
  printf '%d super double-splat case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'super double-splat cases passed\n'
