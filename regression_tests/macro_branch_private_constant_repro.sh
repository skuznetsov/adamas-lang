#!/usr/bin/env bash
# `private LOCALTIME = "/etc/localtime"` sits in the `{% else %}` branch of
# Crystal::System::Time. A constant from a macro branch reaches the module and
# class macro dispatchers wrapped in a VisibilityModifierNode, which matched no
# arm, so the constant was never recorded. Stage 2 stopped with "undefined
# constant LOCALTIME" (File.tempname -> Time.local). The same constant without
# `private`, or `private` outside a macro, already worked.
# Each case exits 42 under original Crystal.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro-private-constant.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

CASES=(module_else_branch module_block_use module_nested_branch class_else_branch class_true_branch)

cat > "$WORK_DIR/module_else_branch.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Fl
  def self.open(x : Int32, &)
    yield x
  end
end
module M
  {% if flag?(:nonexistent_flag) %}
    D = 1
  {% else %}
    private C = 42
    def self.f : Int32
      C
    end
  {% end %}
end
LibC.exit(M.f)
CR

cat > "$WORK_DIR/module_block_use.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class Fl
  def self.open(x : Int32, &)
    yield x
  end
end
module M
  {% if flag?(:nonexistent_flag) %}
    D = 1
  {% else %}
    private C = 42
    def self.f : Int32
      Fl.open(C) { |v| v }
    end
  {% end %}
end
LibC.exit(M.f)
CR

cat > "$WORK_DIR/module_nested_branch.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
module M
  {% if flag?(:nonexistent_flag) %}
    D = 1
  {% else %}
    {% if !flag?(:other_missing_flag) %}
      private C = 42
    {% end %}
    def self.f : Int32
      C
    end
  {% end %}
end
LibC.exit(M.f)
CR

cat > "$WORK_DIR/class_else_branch.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class K
  {% if flag?(:nonexistent_flag) %}
    D = 1
  {% else %}
    private C = 42
    def self.f : Int32
      C
    end
  {% end %}
end
LibC.exit(K.f)
CR

cat > "$WORK_DIR/class_true_branch.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
class K
  {% if true %}
    private C = 42
    def self.f : Int32
      C
    end
  {% end %}
end
LibC.exit(K.f)
CR

exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for name in "${CASES[@]}"; do
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
fi

failures=0

for name in "${CASES[@]}"; do
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --no-prelude "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL %s: compile failed\n' "$name" >&2
    grep -a '^error' "$log" >&2 || tail -3 "$log" >&2
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  got="$(exit_code_of "$run_log")"
  if [[ "$got" == "42" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: exit %s, expected 42\n' "$name" "$got" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%d macro-branch private constant case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all macro-branch private constant cases passed\n'
