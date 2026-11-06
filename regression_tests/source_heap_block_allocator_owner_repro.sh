#!/usr/bin/env bash
# Original-first regression for generated allocator ownership and block ABI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/heap_block_allocator_target"
KNOWN_OPEN_DIR="$FIXTURE_DIR/known_open"
CORE_EXPECTED="$FIXTURE_DIR/expected.json"
KNOWN_OPEN_EXPECTED="$KNOWN_OPEN_DIR/expected.json"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-crystal}}"
CANDIDATE_HINT="${ADAMAS_BIN:-${1:-}}"
ROOT_HINT="${ADAMAS_ROOT_DIR:-}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
RUN_KNOWN_OPEN="${RUN_KNOWN_OPEN:-0}"
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

if [[ "$ORIGINAL_ONLY" != 0 && "$ORIGINAL_ONLY" != 1 ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ "$RUN_KNOWN_OPEN" != 0 && "$RUN_KNOWN_OPEN" != 1 ]]; then
  echo "ERROR: RUN_KNOWN_OPEN must be 0 or 1" >&2
  exit 2
fi
if [[ -z "$CANDIDATE_HINT" && -n "$ROOT_HINT" ]]; then
  CANDIDATE_HINT="$ROOT_HINT/bin/adamas"
fi

if [[ -n "${ADAMAS_SAFE_RUNNER:-}" ]]; then
  SAFE_RUNNER="$ADAMAS_SAFE_RUNNER"
elif [[ -n "$ROOT_HINT" ]]; then
  SAFE_RUNNER="$ROOT_HINT/scripts/run_safe.sh"
elif [[ -n "$CANDIDATE_HINT" && "$CANDIDATE_HINT" == */bin/adamas ]]; then
  SAFE_RUNNER="$(cd "$(dirname "$(dirname "$CANDIDATE_HINT")")" && pwd -P)/scripts/run_safe.sh"
else
  echo "ERROR: set ADAMAS_SAFE_RUNNER or ADAMAS_ROOT_DIR" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" || ! -f "$CORE_EXPECTED" || ! -f "$KNOWN_OPEN_EXPECTED" ]]; then
  echo "ERROR: safe runner or allocator fixture manifests are unavailable" >&2
  echo "Resolved safe runner: $SAFE_RUNNER" >&2
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/heap-allocator-final.XXXXXX")"
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
  local fixture_dir="$1" expected_path="$2" expected_count="$3" expected_negatives="$4" suite="$5"
  python3 - "$expected_path" "$fixture_dir" "$expected_count" "$expected_negatives" "$suite" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
expected_path, fixture_dir = map(Path, sys.argv[1:3])
expected_count, expected_negatives = map(int, sys.argv[3:5])
suite = sys.argv[5]
expected = json.loads(expected_path.read_text())
fixtures = {path.name for path in fixture_dir.glob("*.cr")}
if fixtures != set(expected):
    missing = sorted(set(expected) - fixtures)
    unexpected = sorted(fixtures - set(expected))
    raise SystemExit(f"{suite} fixture manifest mismatch missing={missing} unexpected={unexpected}")
if len(expected) != expected_count:
    raise SystemExit(f"{suite} expected {expected_count} fixtures, found {len(expected)}")
strict_negatives = {
    "self_new_wrong_return.cr": (
        "method-return",
        r"method WrongReturnFactory[.#]new must return Int32,? but it is returning Bool",
    ),
    "default_reject_bottom.cr": (
        "method-return",
        r"method (::)?wrapper must return NoReturn,? but it is returning BottomInitializerToken",
    ),
    "required_reject_bottom.cr": (
        "method-return",
        r"method (::)?wrapper must return NoReturn,? but it is returning BottomInitializerToken",
    ),
    "explicit_default_reject_bottom.cr": (
        "method-return",
        r"method (::)?wrapper must return NoReturn,? but it is returning BottomInitializerToken",
    ),
    "explicit_required_reject_bottom.cr": (
        "method-return",
        r"method (::)?wrapper must return NoReturn,? but it is returning BottomInitializerToken",
    ),
    "explicit_bottom_wrong_argument.cr": (
        "argument-type",
        r"(expected argument #1 to 'consume' to be Int32, not BottomInitializerToken|no overload matches consume for argument types \(BottomInitializerToken\))",
    ),
    "explicit_bottom_via_local.cr": (
        "method-return",
        r"method (::)?wrapper must return NoReturn,? but it is returning BottomInitializerToken",
    ),
}
negative_names = set()
for name, entry in expected.items():
    source_path = fixture_dir / name
    actual_sha = hashlib.sha256(source_path.read_bytes()).hexdigest()
    if actual_sha != entry.get("source_sha256"):
        raise SystemExit(f"{suite} source SHA-256 mismatch for {name}: {actual_sha}")
    status = entry.get("status")
    if status == 0:
        if not isinstance(entry.get("stdout"), str):
            raise SystemExit(f"{suite} missing runtime stdout assertion for {name}")
    elif status == 1:
        negative_names.add(name)
        if suite != "core" or name not in strict_negatives:
            raise SystemExit(f"{suite} contains an unapproved negative fixture: {name}")
        category, diagnostic = strict_negatives[name]
        if entry.get("diagnostic_category") != category or entry.get("diagnostic_regex") != diagnostic:
            raise SystemExit(f"{suite} wrong semantic diagnostic assertion for {name}")
    else:
        raise SystemExit(f"{suite} invalid compiler status for {name}: {status!r}")
if len(negative_names) != expected_negatives:
    raise SystemExit(f"{suite} expected {expected_negatives} strict negatives, found {len(negative_names)}")
if suite == "core" and negative_names != set(strict_negatives):
    raise SystemExit(f"core negative set changed: {sorted(negative_names)}")
PY
}

run_compiler_safely() {
  local phase="$1" cache_dir="$2" compiler="$3"
  shift 3
  local -a environment
  environment=(
    "PATH=$PATH" "HOME=$ISOLATED_HOME" "TMPDIR=$ISOLATED_TMP"
    "LANG=C" "LC_ALL=C" "NO_COLOR=1" "CRYSTAL_CACHE_DIR=$cache_dir"
  )
  [[ -z "$CRYSTAL_PATH_HINT" ]] || environment+=("CRYSTAL_PATH=$CRYSTAL_PATH_HINT")
  [[ "$phase" != candidate ]] || environment+=("ADAMAS_EXTRA_LINK_FLAGS=$CANDIDATE_LINK_FLAGS")
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
  local name source output log stdout stderr expected_stdout cache status expected_status diagnostic_regex expected_run_exit run_status
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
        printf 'FAIL %s %s rejected source left an output executable: %s\n' "$phase_label" "$name" "$output" >&2
        return 1
      fi
      printf 'PASS %s strict-reject %s\n' "$phase_label" "$name"
      count=$((count + 1))
      continue
    fi

    if [[ ! -f "$output" || ! -x "$output" ]]; then
      printf 'FAIL %s %s successful compile did not create an executable: %s\n' "$phase_label" "$name" "$output" >&2
      cat "$log" >&2
      return 1
    fi
    python3 - "$expected_path" "$name" >"$expected_stdout" <<'PY'
import json
import sys
entry = json.load(open(sys.argv[1]))[sys.argv[2]]
sys.stdout.write(entry["stdout"])
PY
    expected_run_exit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]].get("run_exit", 0))' "$expected_path" "$name")"
    run_status=0
    if run_program_safely "$output" "$stdout" "$stderr"; then
      :
    else
      run_status=$?
    fi
    if [[ "$run_status" != "$expected_run_exit" ]]; then
      printf 'FAIL %s %s program_exit=%s expected=%s\n' "$phase_label" "$name" "$run_status" "$expected_run_exit" >&2
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
for name in sorted(json.load(open(sys.argv[1]))):
    print(name)
PY
)
  printf 'HEAP_ALLOCATOR_%s_PASS fixtures=%s compiler=%s\n' \
    "${phase_label//-/_}" "$count" "$compiler"
}

validate_suite "$FIXTURE_DIR" "$CORE_EXPECTED" 27 7 core
validate_suite "$KNOWN_OPEN_DIR" "$KNOWN_OPEN_EXPECTED" 2 0 known_open

# Stock Crystal runs the entire oracle packet before any candidate invocation.
run_suite original "$ORIGINAL" "$FIXTURE_DIR" "$CORE_EXPECTED" original-core
run_suite original "$ORIGINAL" "$KNOWN_OPEN_DIR" "$KNOWN_OPEN_EXPECTED" original-known-open
printf 'HEAP_ALLOCATOR_CANDIDATE_OPEN_EXCLUDED count=2 reason=known-open self.new class/union cases are stock-only by default\n'

if [[ "$ORIGINAL_ONLY" == 1 ]]; then
  printf 'HEAP_ALLOCATOR_ORIGINAL_ONLY candidate_not_run=1 candidate_open_excluded=2\n'
  exit 0
fi
if [[ -z "$CANDIDATE_HINT" ]]; then
  echo "ERROR: candidate compiler is required unless ORIGINAL_ONLY=1" >&2
  echo "Set ADAMAS_ROOT_DIR or pass the candidate compiler path." >&2
  exit 2
fi
CANDIDATE="$(resolve_executable "$CANDIDATE_HINT")" || {
  echo "ERROR: candidate compiler is unavailable: $CANDIDATE_HINT" >&2
  exit 2
}
run_suite candidate "$CANDIDATE" "$FIXTURE_DIR" "$CORE_EXPECTED" candidate-core-only
if [[ "$RUN_KNOWN_OPEN" == 1 ]]; then
  echo 'INFO: RUN_KNOWN_OPEN=1 opts into stock-qualified cases excluded from the core candidate gate.'
  run_suite candidate "$CANDIDATE" "$KNOWN_OPEN_DIR" "$KNOWN_OPEN_EXPECTED" candidate-known-open-optional
fi
