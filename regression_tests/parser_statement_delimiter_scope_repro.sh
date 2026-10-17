#!/usr/bin/env bash
# Original-first statement-boundary regression for delimiter scopes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FIXTURE_DIR="$SCRIPT_DIR/parser_statement_delimiter_scope"
ADAMAS_ROOT="${ADAMAS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
[[ -n "$ADAMAS_ROOT" ]] || { echo 'set ADAMAS_ROOT to the Adamas checkout' >&2; exit 2; }
SAFE="${ADAMAS_RUN_SAFE:-$ADAMAS_ROOT/scripts/run_safe.sh}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
PRISTINE_CRYSTAL_PATH="${PRISTINE_CRYSTAL_PATH:-${CRYSTAL_PATH:-$ADAMAS_ROOT/../crystal/src}}"

case "${1:-}" in
  --original-only)
    [[ "$#" -eq 1 ]] || { echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2; exit 2; }
    CANDIDATE=""
    ;;
  --candidate)
    [[ "$#" -eq 2 && -n "$2" ]] || { echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2; exit 2; }
    CANDIDATE="$2"
    ;;
  "") CANDIDATE="${ADAMAS_BIN:-$ADAMAS_ROOT/bin/adamas}" ;;
  -*) echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2; exit 2 ;;
  *) [[ "$#" -eq 1 ]] || { echo 'usage: $0 [--original-only | [--candidate] COMPILER]' >&2; exit 2; }; CANDIDATE="$1" ;;
esac

[[ -x "$SAFE" && -x "$ORIGINAL" && -d "$PRISTINE_CRYSTAL_PATH" ]] || {
  echo 'set ADAMAS_ROOT, ORIGINAL_CRYSTAL_BIN, and PRISTINE_CRYSTAL_PATH to pinned paths' >&2
  exit 2
}
if [[ -n "$CANDIDATE" && ! -x "$CANDIDATE" ]]; then
  echo "candidate compiler is not executable: $CANDIDATE" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/parser-statement-scope.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK/original.cache" "$WORK/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

cat >"$WORK/run_program" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
exec "$1" 2>"$2"
RUNNER
chmod +x "$WORK/run_program"

DEFAULT_LINK_FLAGS=""
[[ "$(uname -s)" != Darwin ]] || DEFAULT_LINK_FLAGS=-fuse-ld=/usr/bin/ld
ORIGINAL_LINK_FLAGS="${ORIGINAL_LINK_FLAGS:-${CRYSTAL_LINK_FLAGS:-$DEFAULT_LINK_FLAGS}}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:-${CRYSTAL_LINK_FLAGS:-$DEFAULT_LINK_FLAGS}}"

compile_run_compare() {
  local fixture="$1" expected="$2" name="$3"
  local original_bin="$WORK/$name.original.bin"
  local candidate_bin="$WORK/$name.candidate.bin"
  local -a original_args=(build "$fixture" --single-module --no-debug -o "$original_bin")
  [[ -z "$ORIGINAL_LINK_FLAGS" ]] || original_args+=("--link-flags=$ORIGINAL_LINK_FLAGS")
  if ! env CRYSTAL_PATH="$PRISTINE_CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$WORK/original.cache" \
      "$SAFE" "$ORIGINAL" 180 8192 "${original_args[@]}" >"$WORK/$name.original.compile.log" 2>&1; then
    echo "FAIL: original Crystal rejected $name" >&2
    tail -50 "$WORK/$name.original.compile.log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 15 1024 \
      "$original_bin" "$WORK/$name.original.stderr" >"$WORK/$name.original.stdout" 2>"$WORK/$name.original.run.log"; then
    echo "FAIL: original executable failed for $name" >&2
    cat "$WORK/$name.original.run.log" >&2
    return 1
  fi
  if [[ -s "$WORK/$name.original.stderr" ]] || ! cmp -s "$expected" "$WORK/$name.original.stdout"; then
    echo "FAIL: original output did not match the pinned expectation for $name" >&2
    od -An -tx1c "$WORK/$name.original.stdout" >&2
    [[ ! -s "$WORK/$name.original.stderr" ]] || cat "$WORK/$name.original.stderr" >&2
    return 1
  fi
  [[ -z "$CANDIDATE" ]] && return 0

  if ! env CRYSTAL_PATH="$PRISTINE_CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$WORK/candidate.cache" ADAMAS_LLVM_CACHE=0 \
      "$SAFE" "$CANDIDATE" 180 8192 "$fixture" --no-ast-cache --no-llvm-cache --no-debug --no-prelude \
      -o "$candidate_bin" >"$WORK/$name.candidate.compile.log" 2>&1; then
    echo "FAIL: candidate compiler rejected $name" >&2
    tail -50 "$WORK/$name.candidate.compile.log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 15 1024 \
      "$candidate_bin" "$WORK/$name.candidate.stderr" >"$WORK/$name.candidate.stdout" 2>"$WORK/$name.candidate.run.log"; then
    echo "FAIL: candidate executable failed for $name" >&2
    cat "$WORK/$name.candidate.run.log" >&2
    return 1
  fi
  if [[ -s "$WORK/$name.candidate.stderr" ]] || ! cmp -s "$WORK/$name.original.stdout" "$WORK/$name.candidate.stdout"; then
    echo "FAIL: candidate output differs from original for $name" >&2
    od -An -tx1c "$WORK/$name.candidate.stdout" >&2
    [[ ! -s "$WORK/$name.candidate.stderr" ]] || cat "$WORK/$name.candidate.stderr" >&2
    return 1
  fi
  rm -rf "$WORK/original.cache" "$WORK/candidate.cache"
}

printf '/\n' >"$WORK/direct.expected"
printf '=\n' >"$WORK/delimiters.expected"
printf '/\n' >"$WORK/nested.expected"
printf '/10\n' >"$WORK/branches.expected"

compile_run_compare "$FIXTURE_DIR/direct_if_body.cr" "$WORK/direct.expected" direct_if_body
compile_run_compare "$FIXTURE_DIR/operator_continuation_and_body.cr" "$WORK/direct.expected" operator_continuation_and_body
compile_run_compare "$FIXTURE_DIR/multiline_delimiters.cr" "$WORK/delimiters.expected" multiline_delimiters
compile_run_compare "$FIXTURE_DIR/nested_control_bodies.cr" "$WORK/nested.expected" nested_control_bodies
compile_run_compare "$FIXTURE_DIR/opposite_branches.cr" "$WORK/branches.expected" opposite_branches

if [[ -z "$CANDIDATE" ]]; then
  echo 'PASS: original-first statement delimiter fixtures are qualified'
else
  echo 'PASS: candidate preserves original multiline statement and local-delimiter behavior'
fi
