#!/usr/bin/env bash
# `super` inside `def self.m` must call the nearest ancestor class method `m`
# (declared there or acquired through `extend`), with `self` still the
# subclass. The lookup only knew instance methods (`Owner#m`), so every
# class-method super failed with "undefined method 'm' for P"; 1.22.1's
# `File::Error.new_from_os_error` supers into `SystemError::ClassMethods`.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/class-method-super.XXXXXX")"
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
CR

write_case() {
  { cat "$WORK_DIR/header.cr"; printf '%s\n' "$2"; } > "$WORK_DIR/$1.cr"
}

write_case explicit_args '
class P
  def self.make(a : Int32, b : Int32) : Int32
    a + b
  end
end

class K < P
  def self.make(a : Int32, b : Int32) : Int32
    super a, b + 1
  end
end

LibC.exit(K.make(2, 39))'

write_case implicit_args '
class P
  def self.make(a : Int32, b : Int32) : Int32
    a + b
  end
end

class K < P
  def self.make(a : Int32, b : Int32) : Int32
    super
  end
end

LibC.exit(K.make(2, 40))'

write_case self_stays_subclass '
class P
  def self.build(v : Int32)
    new
  end

  def tag : Int32
    0
  end
end

class K < P
  def self.build(v : Int32)
    super(v + 1)
  end

  def tag : Int32
    41
  end
end

LibC.exit(K.build(1).tag + 1)'

write_case chained_supers '
class G
  def self.v(a : Int32) : Int32
    a
  end
end

class P < G
  def self.v(a : Int32) : Int32
    super(a) + 1
  end
end

class K < P
  def self.v(a : Int32) : Int32
    super(a) + 1
  end
end

LibC.exit(K.v(40))'

write_case extended_ancestor '
module M
  def v(a : Int32) : Int32
    a + 2
  end
end

class P
  extend M
end

class K < P
  def self.v(a : Int32) : Int32
    super(a)
  end
end

LibC.exit(K.v(40))'

CASES=(explicit_args:42 implicit_args:42 self_stays_subclass:42 chained_supers:42 extended_ancestor:42)

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
  printf '%d class-method super case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'class-method super cases passed\n'
