#!/usr/bin/env bash
# Method lookup must preserve the requested class/instance separator.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/class-instance-method-lookup.XXXXXX")"
ORIGINAL_LINK_ARGS=()
[[ "$(uname -s)" != Darwin ]] || ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
cleanup() {
  local status=$?
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL" ]] || exit 2

cat >"$WORK/separators.cr" <<'CRYSTAL'
@[Link("c")]
lib MethodSeparatorOutput
  fun putchar(value : Int32) : Int32
end

class MethodSeparatorRoot
  def self.probe : Int32
    65
  end
end

class MethodSeparatorChild < MethodSeparatorRoot
  def probe : Int32
    66
  end
end

module MethodSeparatorExport
  extend self

  def exported_probe : Int32
    67
  end
end

MethodSeparatorOutput.putchar(MethodSeparatorChild.probe)
MethodSeparatorOutput.putchar(MethodSeparatorChild.new.probe)
MethodSeparatorOutput.putchar(MethodSeparatorExport.exported_probe)
MethodSeparatorOutput.putchar(10)
CRYSTAL

cat >"$WORK/instance_as_class.cr" <<'CRYSTAL'
class InstanceOnlySeparatorProbe
  def instance_only_separator_probe : Int32
    65
  end
end

InstanceOnlySeparatorProbe.instance_only_separator_probe
CRYSTAL

cat >"$WORK/class_as_instance.cr" <<'CRYSTAL'
class ClassOnlySeparatorProbe
  def self.class_only_separator_probe : Int32
    65
  end
end

ClassOnlySeparatorProbe.new.class_only_separator_probe
CRYSTAL

printf 'ABC\n' >"$WORK/expected"

compile_case() {
  local mode="$1" name="$2" status=0
  local -a command_args mode_env
  mode_env=(env)
  if [[ "$mode" == original ]]; then
    command_args=("$ORIGINAL" 120 8192 build --prelude=empty --no-debug "${ORIGINAL_LINK_ARGS[@]}")
  else
    command_args=("$COMPILER" 120 4096 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    if [[ "$mode" == eager ]]; then
      mode_env+=(ADAMAS_EAGER_MONO=1)
    else
      mode_env+=(-u ADAMAS_EAGER_MONO)
    fi
  fi
  mode_env+=(ADAMAS_LLVM_CACHE=0)
  CRYSTAL_CACHE_DIR="$WORK/cache.$mode.$name" "${mode_env[@]}" \
    "$SAFE_RUNNER" "${command_args[@]}" "$WORK/$name.cr" -o "$WORK/$mode.$name.bin" \
    >"$WORK/$mode.$name.compile.log" 2>&1 || status=$?
  return "$status"
}

run_positive() {
  local mode="$1"
  if ! compile_case "$mode" separators; then
    cat "$WORK/$mode.separators.compile.log" >&2
    return 1
  fi
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK/$mode.separators.bin" 5 512 \
    >"$WORK/$mode.separators.stdout" 2>"$WORK/$mode.separators.run.log" || {
      cat "$WORK/$mode.separators.run.log" >&2
      return 1
    }
  diff -u "$WORK/expected" "$WORK/$mode.separators.stdout"
}

reject_cross_separator() {
  local mode="$1" name="$2" expected_method="$3" status=0
  compile_case "$mode" "$name" || status=$?
  if [[ "$status" == 0 || -e "$WORK/$mode.$name.bin" ]]; then
    cat "$WORK/$mode.$name.compile.log" >&2
    echo "FAIL[$mode]: accepted cross-separator call in $name" >&2
    return 1
  fi
  python3 - "$WORK/$mode.$name.compile.log" "$expected_method" <<'PY_REJECT'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace").lower()
method = sys.argv[2].lower()
assert method in text, text
assert any(marker in text for marker in (
    "undefined method", "no overload", "can't resolve", "cannot resolve",
)), text
assert "syntax error" not in text and "parser errors" not in text, text
PY_REJECT
}

failures=0
run_positive original || failures=1
reject_cross_separator original instance_as_class instance_only_separator_probe || failures=1
reject_cross_separator original class_as_instance class_only_separator_probe || failures=1
if [[ "$failures" != 0 ]]; then
  echo "FAIL[original]: separator oracle mismatch" >&2
  exit 1
fi
echo "PASS[original]: dotted/instance overload choice, extend-self export, and opposite-separator rejection"

failures=0
for mode in lazy eager; do
  mode_failures=0
  run_positive "$mode" || mode_failures=1
  reject_cross_separator "$mode" instance_as_class instance_only_separator_probe || mode_failures=1
  reject_cross_separator "$mode" class_as_instance class_only_separator_probe || mode_failures=1
  if [[ "$mode_failures" != 0 ]]; then
    failures=1
    echo "FAIL[$mode]: class/instance separator lookup mismatch" >&2
  else
    echo "PASS[$mode]: dotted/instance overload choice, extend-self export, and opposite-separator rejection"
  fi
done

exit "$failures"
