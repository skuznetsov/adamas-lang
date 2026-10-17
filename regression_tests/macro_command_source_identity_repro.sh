#!/usr/bin/env bash
# Original-first command evaluation and generated-source identity regression.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
FIXTURE_DIR="$SCRIPT_DIR/macro_command_source_identity"
SAFE="${ADAMAS_RUN_SAFE:-$ROOT/scripts/run_safe.sh}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CANDIDATE="${1:?usage: macro_command_source_identity_repro.sh <candidate> | --original-only}"
[[ -x "$SAFE" && -x "$ORIGINAL" ]] || { echo 'safe runner and original Crystal required' >&2; exit 2; }
[[ "$CANDIDATE" == --original-only || -x "$CANDIDATE" ]] || exit 2
if [[ -z "${CRYSTAL_PATH:-}" && -d "$ROOT/../crystal/src" ]]; then export CRYSTAL_PATH="$ROOT/../crystal/src"; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/macro-command-source.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK/original.cache" "$WORK/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else rm -rf "$WORK"; fi
}
trap cleanup EXIT
cat >"$WORK/run_program" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exec "$1" 2>"$2"
SH
chmod +x "$WORK/run_program"
compile() {
  local stage="$1" fixture="$2" output="$3" log="$4" status=0
  local -a args
  if [[ "$stage" == original ]]; then
    args=(build "$FIXTURE_DIR/$fixture.cr" --single-module --no-debug -o "$output")
    if [[ -n "${ADAMAS_ORIGINAL_LINK_FLAGS:-}" ]]; then args+=("--link-flags=$ADAMAS_ORIGINAL_LINK_FLAGS")
    elif [[ "$(uname -s)" == Darwin ]]; then args+=(--link-flags=-fuse-ld=/usr/bin/ld); fi
    CRYSTAL_CACHE_DIR="$WORK/original.cache" "$SAFE" "$ORIGINAL" 180 8192 "${args[@]}" >"$log" 2>&1 || status=$?
  else
    CRYSTAL_CACHE_DIR="$WORK/candidate.cache" ADAMAS_LLVM_CACHE=0 "$SAFE" "$CANDIDATE" 180 8192 \
      "$FIXTURE_DIR/$fixture.cr" --no-prelude --no-ast-cache --no-llvm-cache --no-debug -o "$output" >"$log" 2>&1 || status=$?
  fi
  return "$status"
}
check_stage() {
  local stage="$1" positive output compile_log
  for positive in command_evaluation generated_nested_macro; do
    output="$WORK/$stage.$positive.bin"
    compile_log="$WORK/$stage.$positive.compile.log"
    if ! compile "$stage" "$positive" "$output" "$compile_log"; then
      echo "FAIL $stage rejected $positive" >&2
      tail -40 "$compile_log" >&2
      return 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 15 1024 "$output" "$WORK/$stage.$positive.stderr" \
        >"$WORK/$stage.$positive.stdout" 2>"$WORK/$stage.$positive.runner.log"; then
      echo "FAIL $stage executable failed for $positive" >&2
      tail -30 "$WORK/$stage.$positive.runner.log" >&2
      return 1
    fi
    if [[ -s "$WORK/$stage.$positive.stderr" ]] || ! cmp -s "$FIXTURE_DIR/$positive.stdout" "$WORK/$stage.$positive.stdout"; then
      echo "FAIL $stage output differs for $positive" >&2
      diff -u "$FIXTURE_DIR/$positive.stdout" "$WORK/$stage.$positive.stdout" >&2 || true
      cat "$WORK/$stage.$positive.stderr" >&2
      return 1
    fi
  done
  local fixture bad_output bad_log rc
  for fixture in failed_command failed_assigned_command failed_interpolated_command failed_generated_command; do
    bad_output="$WORK/$stage.$fixture.bin"
    bad_log="$WORK/$stage.$fixture.log"
    rc=0
    compile "$stage" "$fixture" "$bad_output" "$bad_log" || rc=$?
    if [[ "$rc" -ne 1 || -e "$bad_output" ]]; then
      echo "FAIL $stage must reject $fixture before executable emission (rc=$rc)" >&2
      tail -40 "$bad_log" >&2
      return 1
    fi
    if ! rg -qi 'execut.*command|command.*fail' "$bad_log"; then
      echo "FAIL $stage failed-command diagnostic missing for $fixture" >&2
      tail -40 "$bad_log" >&2
      return 1
    fi
  done
}
check_stage original
if [[ "$CANDIDATE" != --original-only ]]; then
  check_stage candidate
  for positive in command_evaluation generated_nested_macro; do
    cmp -s "$WORK/original.$positive.stdout" "$WORK/candidate.$positive.stdout"
  done
  printf 'PASS: direct/assigned/generated command semantics, inert strings, separate source buffers and direct/assigned/interpolated/generated command failures\n'
else printf 'PASS: original qualified command semantics and rejection fixtures\n'; fi
