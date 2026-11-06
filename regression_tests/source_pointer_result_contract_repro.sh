#!/usr/bin/env bash
# Postfix pointer result restrictions share the generic Pointer contract.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FIXTURE_DIR="$ROOT_DIR/regression_tests/fixtures/source_pointer_result_contract"
EXPECTED="$FIXTURE_DIR/expected.json"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
CANDIDATE_HINT="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-180}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
PROGRAM_TIMEOUT_SEC="${PROGRAM_TIMEOUT_SEC:-5}"
PROGRAM_MAX_MEM_MB="${PROGRAM_MAX_MEM_MB:-512}"
CANDIDATE_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:-}"
ORIGINAL_LINK_FLAGS="${ORIGINAL_CRYSTAL_LINK_FLAGS:-}"

cd "$ROOT_DIR"

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

if [[ "$ORIGINAL_ONLY" != 0 && "$ORIGINAL_ONLY" != 1 ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" || ! -f "$EXPECTED" || ! -d "$FIXTURE_DIR" ]]; then
  echo "ERROR: safe runner or source-pointer-result fixtures are unavailable" >&2
  exit 2
fi
ORIGINAL="$(resolve_executable "$ORIGINAL_HINT")" || {
  echo "ERROR: original Crystal compiler is unavailable: $ORIGINAL_HINT" >&2
  exit 2
}
if [[ "$ORIGINAL_ONLY" != 1 ]]; then
  CANDIDATE="$(resolve_executable "$CANDIDATE_HINT")" || {
    echo "ERROR: candidate compiler is unavailable: $CANDIDATE_HINT" >&2
    exit 2
  }
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/source-pointer-result-contract.XXXXXX")"
mkdir -p "$WORK_DIR/home" "$WORK_DIR/tmp"
ISOLATED_HOME="$WORK_DIR/home"
ISOLATED_TMP="$WORK_DIR/tmp"

cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache-*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

python3 - "$EXPECTED" "$FIXTURE_DIR" <<'PY'
import json
from pathlib import Path
import sys

expected_path, fixture_dir = map(Path, sys.argv[1:])
expected = json.loads(expected_path.read_text())
fixtures = {path.name for path in fixture_dir.glob("*.cr")}
if fixtures != set(expected):
    missing = sorted(set(expected) - fixtures)
    unexpected = sorted(fixtures - set(expected))
    raise SystemExit(f"fixture manifest mismatch missing={missing} unexpected={unexpected}")
for name, entry in expected.items():
    status = entry.get("status")
    if status not in (0, 1):
        raise SystemExit(f"invalid expected compiler status for {name}: {status!r}")
    if status == 0 and not isinstance(entry.get("stdout"), str):
        raise SystemExit(f"missing runtime stdout assertion for positive fixture {name}")
    if status == 1 and not entry.get("diagnostic"):
        raise SystemExit(f"missing rejection diagnostic for negative fixture {name}")
PY

if [[ "$(uname -s)" == Darwin ]]; then
  [[ -n "$ORIGINAL_LINK_FLAGS" ]] || ORIGINAL_LINK_FLAGS="-fuse-ld=/usr/bin/ld"
  [[ -n "$CANDIDATE_LINK_FLAGS" ]] || CANDIDATE_LINK_FLAGS="-fuse-ld=/usr/bin/ld"
fi

run_compiler_safely() {
  local cache_dir="$1" compiler="$2"
  shift 2
  mkdir -p "$cache_dir"
  env -i \
    PATH="$PATH" HOME="$ISOLATED_HOME" TMPDIR="$ISOLATED_TMP" \
    LANG=C LC_ALL=C NO_COLOR=1 CRYSTAL_CACHE_DIR="$cache_dir" \
    ADAMAS_EXTRA_LINK_FLAGS="$CANDIDATE_LINK_FLAGS" \
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
  local phase="$1" compiler="$2" source name output log stdout stderr expected_stdout
  local expected_status expected_diagnostic status count=0 cache phase_label

  case "$phase" in
    original) phase_label=ORIGINAL ;;
    candidate) phase_label=CANDIDATE ;;
    *) echo "ERROR: unknown suite phase: $phase" >&2; return 2 ;;
  esac

  for source in "$FIXTURE_DIR"/*.cr; do
    name="$(basename "$source")"
    output="$WORK_DIR/$phase-${name%.cr}"
    log="$WORK_DIR/$phase-${name%.cr}.compile.log"
    stdout="$WORK_DIR/$phase-${name%.cr}.stdout"
    stderr="$WORK_DIR/$phase-${name%.cr}.stderr"
    expected_stdout="$WORK_DIR/$phase-${name%.cr}.expected"
    cache="$WORK_DIR/cache-$phase-${name%.cr}"
    expected_status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["status"])' "$EXPECTED" "$name")"
    expected_diagnostic="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]].get("diagnostic", ""))' "$EXPECTED" "$name")"
    rm -f -- "$output" "$stdout" "$stderr" "$expected_stdout"

    args=()
    if [[ "$phase" == original ]]; then
      args=(build --prelude=empty --no-debug --error-trace)
    else
      args=("$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    fi
    if [[ "$phase" == original ]]; then
      if [[ -n "$ORIGINAL_LINK_FLAGS" ]]; then
        args+=("--link-flags=$ORIGINAL_LINK_FLAGS")
      fi
      args+=("$source")
    fi
    args+=(-o "$output")

    status=0
    if run_compiler_safely "$cache" "$compiler" "${args[@]}" >"$log" 2>&1; then
      :
    else
      status=$?
    fi

    if [[ "$status" != "$expected_status" ]]; then
      printf 'FAIL %s %s compiler_status=%s expected=%s log=%s\n' \
        "$phase" "$name" "$status" "$expected_status" "$log" >&2
      cat "$log" >&2
      return 1
    fi

    if [[ "$expected_status" == 1 ]]; then
      if ! grep -Fq -- "$expected_diagnostic" "$log"; then
        printf 'FAIL %s %s missing_diagnostic=%s log=%s\n' \
          "$phase" "$name" "$expected_diagnostic" "$log" >&2
        cat "$log" >&2
        return 1
      fi
      if [[ -e "$output" || -L "$output" ]]; then
        printf 'FAIL %s %s rejected source left an output artifact: %s\n' \
          "$phase" "$name" "$output" >&2
        return 1
      fi
      printf 'PASS %s reject %s\n' "$phase" "$name"
      count=$((count + 1))
      continue
    fi

    if [[ ! -f "$output" || ! -x "$output" ]]; then
      printf 'FAIL %s %s successful compile did not create an executable: %s\n' \
        "$phase" "$name" "$output" >&2
      cat "$log" >&2
      return 1
    fi
    python3 - "$EXPECTED" "$name" >"$expected_stdout" <<'PY'
import json
import sys
entry = json.load(open(sys.argv[1]))[sys.argv[2]]
sys.stdout.write(entry["stdout"])
PY
    if ! run_program_safely "$output" "$stdout" "$stderr"; then
      printf 'FAIL %s %s program execution failed\n' "$phase" "$name" >&2
      cat "$stderr" >&2
      return 1
    fi
    if ! cmp -s "$expected_stdout" "$stdout"; then
      printf 'FAIL %s %s runtime output mismatch expected=%s actual=%s\n' \
        "$phase" "$name" "$expected_stdout" "$stdout" >&2
      printf '%s\n' '--- expected ---' >&2
      cat "$expected_stdout" >&2
      printf '%s\n' '--- actual ---' >&2
      cat "$stdout" >&2
      return 1
    fi
    printf 'PASS %s compile+run %s\n' "$phase" "$name"
    count=$((count + 1))
  done
  printf 'SOURCE_POINTER_RESULT_CONTRACT_%s_PASS fixtures=%s compiler=%s\n' \
    "$phase_label" "$count" "$compiler"
}

run_suite original "$ORIGINAL"
if [[ "$ORIGINAL_ONLY" != 1 ]]; then
  run_suite candidate "$CANDIDATE"
fi
