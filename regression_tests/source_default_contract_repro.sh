#!/usr/bin/env bash
# Original-first regression for canonical source facts on default arguments.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/source_default_contract"
OPEN_DIR="$FIXTURE_DIR/open_companions"
EXPECTED="$FIXTURE_DIR/expected.json"
OPEN_EXPECTED="$OPEN_DIR/expected.json"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
CANDIDATE_HINT="${ADAMAS_BIN:-${1:-}}"
ROOT_HINT="${ADAMAS_ROOT_DIR:-}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-180}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
PROGRAM_TIMEOUT_SEC="${PROGRAM_TIMEOUT_SEC:-5}"
PROGRAM_MAX_MEM_MB="${PROGRAM_MAX_MEM_MB:-512}"
ORIGINAL_LINK_FLAGS="${ORIGINAL_CRYSTAL_LINK_FLAGS:-}"
CANDIDATE_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:-}"
CRYSTAL_PATH_HINT="${CRYSTAL_PATH:-}"

resolve_executable() {
  local hint="$1" resolved
  if [[ "$hint" == */* ]]; then
    [[ -x "$hint" ]] || return 1
    resolved="$(cd "$(dirname "$hint")" && pwd -P)/$(basename "$hint")"
  else
    resolved="$(command -v "$hint" || true)"
    [[ -n "$resolved" && -x "$resolved" ]] || return 1
  fi
  printf '%s\n' "$resolved"
}

if [[ -z "$CANDIDATE_HINT" ]]; then
  if [[ -n "$ROOT_HINT" ]]; then
    CANDIDATE_HINT="$ROOT_HINT/bin/adamas"
  else
    CANDIDATE_HINT="$BUNDLE_ROOT/bin/adamas"
  fi
fi
CANDIDATE="$(resolve_executable "$CANDIDATE_HINT")" || {
  echo "ERROR: candidate compiler is unavailable: $CANDIDATE_HINT" >&2
  echo "Set ADAMAS_ROOT_DIR or pass the candidate compiler path." >&2
  exit 2
}

if [[ -n "$ROOT_HINT" ]]; then
  ROOT_DIR="$(cd "$ROOT_HINT" && pwd -P)"
else
  candidate_dir="$(dirname "$CANDIDATE")"
  if [[ "$(basename "$candidate_dir")" == "bin" ]]; then
    ROOT_DIR="$(cd "$candidate_dir/.." && pwd -P)"
  else
    ROOT_DIR="$BUNDLE_ROOT"
  fi
fi
SAFE_RUNNER="${ADAMAS_SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"

if [[ "$ORIGINAL_ONLY" != 0 && "$ORIGINAL_ONLY" != 1 ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" || ! -f "$EXPECTED" || ! -f "$OPEN_EXPECTED" || ! -d "$FIXTURE_DIR" || ! -d "$OPEN_DIR" ]]; then
  echo "ERROR: safe runner or source-default-contract fixtures are unavailable" >&2
  echo "Resolved repository root: $ROOT_DIR" >&2
  exit 2
fi
ORIGINAL="$(resolve_executable "$ORIGINAL_HINT")" || {
  echo "ERROR: original Crystal compiler is unavailable: $ORIGINAL_HINT" >&2
  exit 2
}

if [[ "$(uname -s)" == Darwin ]]; then
  [[ -n "$ORIGINAL_LINK_FLAGS" ]] || ORIGINAL_LINK_FLAGS="-fuse-ld=/usr/bin/ld"
  [[ -n "$CANDIDATE_LINK_FLAGS" ]] || CANDIDATE_LINK_FLAGS="-fuse-ld=/usr/bin/ld"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/source-default-contract.XXXXXX")"
mkdir -p "$WORK_DIR/home" "$WORK_DIR/tmp"
ISOLATED_HOME="$WORK_DIR/home"
ISOLATED_TMP="$WORK_DIR/tmp"

cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

validate_suite() {
  local fixture_dir="$1" expected_path="$2" expected_count="$3"
  python3 - "$expected_path" "$fixture_dir" "$expected_count" <<'PY'
import json
from pathlib import Path
import sys
expected_path, fixture_dir = map(Path, sys.argv[1:3])
expected_count = int(sys.argv[3])
expected = json.loads(expected_path.read_text())
fixtures = {path.name for path in fixture_dir.glob("*.cr")}
if fixtures != set(expected):
    missing = sorted(set(expected) - fixtures)
    unexpected = sorted(fixtures - set(expected))
    raise SystemExit(f"fixture manifest mismatch missing={missing} unexpected={unexpected}")
if len(expected) != expected_count:
    raise SystemExit(f"expected {expected_count} fixtures, found {len(expected)}")
for name, entry in expected.items():
    status = entry.get("status")
    if status == 0:
        if not isinstance(entry.get("stdout"), str):
            raise SystemExit(f"missing runtime stdout assertion for {name}")
    elif status == 1:
        if not entry.get("diagnostic_regex"):
            raise SystemExit(f"missing semantic diagnostic assertion for {name}")
    else:
        raise SystemExit(f"invalid expected compiler status for {name}: {status!r}")
PY
}
validate_suite "$FIXTURE_DIR" "$EXPECTED" 37
validate_suite "$OPEN_DIR" "$OPEN_EXPECTED" 5

run_compiler_safely() {
  local phase="$1" cache_dir="$2" compiler="$3"
  shift 3
  local -a environment
  environment=(
    "PATH=$PATH" "HOME=$ISOLATED_HOME" "TMPDIR=$ISOLATED_TMP"
    "LANG=C" "LC_ALL=C" "NO_COLOR=1" "CRYSTAL_CACHE_DIR=$cache_dir"
  )
  if [[ -n "$CRYSTAL_PATH_HINT" ]]; then
    environment+=("CRYSTAL_PATH=$CRYSTAL_PATH_HINT")
  fi
  if [[ "$phase" == candidate ]]; then
    environment+=("ADAMAS_EXTRA_LINK_FLAGS=$CANDIDATE_LINK_FLAGS")
  fi
  env -i "${environment[@]}" \
    "$SAFE_RUNNER" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" "$@"
}

run_program_safely() {
  local binary="$1" stdout_path="$2" stderr_path="$3"
  env -i \
    PATH="$PATH" HOME="$ISOLATED_HOME" TMPDIR="$ISOLATED_TMP" \
    LANG=C LC_ALL=C NO_COLOR=1 RUN_SAFE_PASSTHROUGH_STDIO=1 \
    "$SAFE_RUNNER" "$binary" "$PROGRAM_TIMEOUT_SEC" "$PROGRAM_MAX_MEM_MB" \
    >"$stdout_path" 2>"$stderr_path"
}

run_suite() {
  local phase="$1" compiler="$2" fixture_dir="$3" expected_path="$4" phase_label="$5"
  local name source output log stdout stderr expected_stdout cache status expected_status diagnostic_regex
  local count=0
  while IFS= read -r name; do
    source="$fixture_dir/$name"
    output="$WORK_DIR/$phase-${name%.cr}"
    log="$WORK_DIR/$phase-${name%.cr}.compile.log"
    stdout="$WORK_DIR/$phase-${name%.cr}.stdout"
    stderr="$WORK_DIR/$phase-${name%.cr}.stderr"
    expected_stdout="$WORK_DIR/$phase-${name%.cr}.expected"
    cache="$WORK_DIR/cache-$phase-${name%.cr}"
    expected_status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["status"])' "$expected_path" "$name")"
    diagnostic_regex="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]].get("diagnostic_regex", ""))' "$expected_path" "$name")"
    rm -f -- "$output" "$stdout" "$stderr" "$expected_stdout"

    if [[ "$phase" == original ]]; then
      args=(build --prelude=empty --no-debug --error-trace)
      [[ -z "$ORIGINAL_LINK_FLAGS" ]] || args+=("--link-flags=$ORIGINAL_LINK_FLAGS")
      args+=("$source" -o "$output")
    else
      args=("$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output")
    fi

    status=0
    if run_compiler_safely "$phase" "$cache" "$compiler" "${args[@]}" >"$log" 2>&1; then
      :
    else
      status=$?
    fi

    if [[ "$status" != "$expected_status" ]]; then
      printf 'FAIL %s %s compiler_status=%s expected=%s log=%s\n' \
        "$phase_label" "$name" "$status" "$expected_status" "$log" >&2
      cat "$log" >&2
      return 1
    fi

    if [[ "$expected_status" == 1 ]]; then
      if ! grep -Eiq -- "$diagnostic_regex" "$log"; then
        printf 'FAIL %s %s missing_semantic_diagnostic=%s log=%s\n' \
          "$phase_label" "$name" "$diagnostic_regex" "$log" >&2
        cat "$log" >&2
        return 1
      fi
      if grep -Eiq 'internal compiler error|unhandled exception|segmentation fault|SIGSEGV|resource limit|timed out' "$log"; then
        printf 'FAIL %s %s compiler failed instead of rejecting the source\n' "$phase_label" "$name" >&2
        cat "$log" >&2
        return 1
      fi
      if [[ -e "$output" || -L "$output" ]]; then
        printf 'FAIL %s %s rejected source left an output executable: %s\n' \
          "$phase_label" "$name" "$output" >&2
        return 1
      fi
      printf 'PASS %s reject %s\n' "$phase_label" "$name"
      count=$((count + 1))
      continue
    fi

    if [[ ! -f "$output" || ! -x "$output" ]]; then
      printf 'FAIL %s %s successful compile did not create an executable: %s\n' \
        "$phase_label" "$name" "$output" >&2
      cat "$log" >&2
      return 1
    fi
    python3 - "$expected_path" "$name" >"$expected_stdout" <<'PY'
import json
import sys
entry = json.load(open(sys.argv[1]))[sys.argv[2]]
sys.stdout.write(entry["stdout"])
PY
    if ! run_program_safely "$output" "$stdout" "$stderr"; then
      printf 'FAIL %s %s program execution failed\n' "$phase_label" "$name" >&2
      cat "$stderr" >&2
      return 1
    fi
    if ! cmp -s "$expected_stdout" "$stdout"; then
      printf 'FAIL %s %s runtime output mismatch\n' "$phase_label" "$name" >&2
      printf '%s\n' '--- expected ---' >&2
      cat "$expected_stdout" >&2
      printf '%s\n' '--- actual ---' >&2
      cat "$stdout" >&2
      return 1
    fi
    printf 'PASS %s compile+run %s\n' "$phase_label" "$name"
    count=$((count + 1))
  done < <(python3 - "$expected_path" <<'PY'
import json
import sys
for name in json.load(open(sys.argv[1])):
    print(name)
PY
)
  printf 'SOURCE_DEFAULT_CONTRACT_%s_PASS fixtures=%s compiler=%s\n' \
    "$phase_label" "$count" "$compiler"
}

# Qualify every source expectation with stock Crystal before running Adamas.
run_suite original "$ORIGINAL" "$FIXTURE_DIR" "$EXPECTED" original-main
run_suite original "$ORIGINAL" "$OPEN_DIR" "$OPEN_EXPECTED" original-open-companions
if [[ "$ORIGINAL_ONLY" != 1 ]]; then
  run_suite candidate "$CANDIDATE" "$FIXTURE_DIR" "$EXPECTED" candidate-main
  printf '%s\n' 'OPEN candidate companions: see fixtures/source_default_contract/open_companions/expected.json (excluded from candidate success)'
fi
