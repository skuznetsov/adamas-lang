#!/usr/bin/env bash
# Original-first no-prelude regression for source-method Void result normalization.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/source_method_void_result"
EXPECTED="$FIXTURE_DIR/expected.json"
ABI_SOURCE="$FIXTURE_DIR/abi/fun_main_void.cr"
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

if [[ "$ORIGINAL_ONLY" != 0 && "$ORIGINAL_ONLY" != 1 ]]; then
  echo "ERROR: ORIGINAL_ONLY must be 0 or 1" >&2
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
if [[ ! -x "$SAFE_RUNNER" || ! -f "$EXPECTED" ]]; then
  echo "ERROR: safe runner or helper-result fixture manifest is unavailable" >&2
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/source-method-void-result.XXXXXX")"
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

validate_manifest() {
  python3 - "$EXPECTED" "$FIXTURE_DIR" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
manifest_path, fixture_dir = map(Path, sys.argv[1:3])
entries = json.loads(manifest_path.read_text())
fixtures = {path.name for path in fixture_dir.glob("*.cr")}
if fixtures != set(entries):
    raise SystemExit(f"fixture manifest mismatch missing={sorted(set(entries)-fixtures)} unexpected={sorted(fixtures-set(entries))}")
if len(entries) != 8:
    raise SystemExit(f"expected exactly 8 fixtures, found {len(entries)}")
negative_names = {"reject_parenthesized_void_body_result.cr", "reject_ordinary_void_body_result.cr"}
if {name for name, entry in entries.items() if entry.get("status") == 1} != negative_names:
    raise SystemExit("strict-negative fixture set changed")
for name, entry in entries.items():
    source = fixture_dir / name
    actual = hashlib.sha256(source.read_bytes()).hexdigest()
    if actual != entry.get("source_sha256"):
        raise SystemExit(f"source SHA-256 mismatch for {name}: {actual}")
    status = entry.get("status")
    if status == 0:
        if not isinstance(entry.get("stdout"), str) or entry.get("candidate_status", 0) != 0:
            raise SystemExit(f"missing positive runtime assertion for {name}")
    elif status == 1:
        if entry.get("candidate_status") != 1 or entry.get("diagnostic_category") != "method-return":
            raise SystemExit(f"bad strict-negative contract for {name}")
        for field in ("original_diagnostic_regex", "candidate_diagnostic_regex"):
            if not entry.get(field):
                raise SystemExit(f"missing {field} for {name}")
    else:
        raise SystemExit(f"invalid compiler status for {name}: {status!r}")
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
  env -i PATH="$PATH" HOME="$ISOLATED_HOME" TMPDIR="$ISOLATED_TMP" \
    LANG=C LC_ALL=C NO_COLOR=1 RUN_SAFE_PASSTHROUGH_STDIO=1 \
    "$SAFE_RUNNER" "$binary" "$PROGRAM_TIMEOUT_SEC" "$PROGRAM_MAX_MEM_MB" \
    >"$stdout_path" 2>"$stderr_path"
}

run_suite() {
  local phase="$1" compiler="$2" label="$3"
  local name source output log stdout stderr expected_stdout cache
  local expected_status actual_status diagnostic_regex run_status expected_exit count=0
  while IFS= read -r name; do
    source="$FIXTURE_DIR/$name"
    output="$WORK_DIR/$phase-${name%.cr}"
    log="$WORK_DIR/$phase-${name%.cr}.compile.log"
    stdout="$WORK_DIR/$phase-${name%.cr}.stdout"
    stderr="$WORK_DIR/$phase-${name%.cr}.stderr"
    expected_stdout="$WORK_DIR/$phase-${name%.cr}.expected"
    cache="$WORK_DIR/cache-$phase-${name%.cr}"
    if [[ "$phase" == original ]]; then
      expected_status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["status"])' "$EXPECTED" "$name")"
      diagnostic_regex="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]].get("original_diagnostic_regex", ""))' "$EXPECTED" "$name")"
    else
      expected_status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]].get("candidate_status", 0))' "$EXPECTED" "$name")"
      diagnostic_regex="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]].get("candidate_diagnostic_regex", ""))' "$EXPECTED" "$name")"
    fi
    rm -f -- "$output" "$stdout" "$stderr" "$expected_stdout"

    if [[ "$phase" == original ]]; then
      args=(build --prelude=empty --no-debug --error-trace)
      [[ -z "$ORIGINAL_LINK_FLAGS" ]] || args+=("--link-flags=$ORIGINAL_LINK_FLAGS")
      args+=("$source" -o "$output")
    else
      args=("$source" --no-prelude --no-debug --no-ast-cache --no-llvm-cache -o "$output")
    fi
    actual_status=0
    if run_compiler_safely "$phase" "$cache" "$compiler" "${args[@]}" >"$log" 2>&1; then
      :
    else
      actual_status=$?
    fi
    if [[ "$actual_status" != "$expected_status" ]]; then
      printf 'FAIL %s %s compiler_status=%s expected=%s log=%s\n' "$label" "$name" "$actual_status" "$expected_status" "$log" >&2
      cat "$log" >&2
      return 1
    fi

    if [[ "$expected_status" == 1 ]]; then
      if ! grep -Eiq -- "$diagnostic_regex" "$log"; then
        printf 'FAIL %s %s missing semantic diagnostic: %s\n' "$label" "$name" "$diagnostic_regex" >&2
        cat "$log" >&2
        return 1
      fi
      if grep -Eiq 'internal compiler error|unhandled exception|segmentation fault|SIGSEGV|resource limit|timed out' "$log"; then
        printf 'FAIL %s %s compiler failed instead of rejecting source\n' "$label" "$name" >&2
        cat "$log" >&2
        return 1
      fi
      if [[ -e "$output" || -L "$output" ]]; then
        printf 'FAIL %s %s rejected source left an output executable\n' "$label" "$name" >&2
        return 1
      fi
      printf 'PASS %s strict-reject %s\n' "$label" "$name"
      count=$((count + 1))
      continue
    fi

    if [[ ! -f "$output" || ! -x "$output" ]]; then
      printf 'FAIL %s %s successful compile did not create an executable\n' "$label" "$name" >&2
      cat "$log" >&2
      return 1
    fi
    python3 - "$EXPECTED" "$name" >"$expected_stdout" <<'PY'
import json
import sys
entry = json.load(open(sys.argv[1]))[sys.argv[2]]
sys.stdout.write(entry["stdout"])
PY
    expected_exit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]].get("run_exit", 0))' "$EXPECTED" "$name")"
    run_status=0
    if run_program_safely "$output" "$stdout" "$stderr"; then
      :
    else
      run_status=$?
    fi
    if [[ "$run_status" != "$expected_exit" ]]; then
      printf 'FAIL %s %s program_exit=%s expected=%s\n' "$label" "$name" "$run_status" "$expected_exit" >&2
      cat "$stderr" >&2
      return 1
    fi
    if ! cmp -s "$expected_stdout" "$stdout"; then
      printf 'FAIL %s %s runtime output mismatch\n--- expected ---\n' "$label" "$name" >&2
      cat "$expected_stdout" >&2
      printf '%s\n' '--- actual ---' >&2
      cat "$stdout" >&2
      return 1
    fi
    printf 'PASS %s compile+run %s\n' "$label" "$name"
    count=$((count + 1))
  done < <(python3 - "$EXPECTED" <<'PY'
import json
import sys
for name in sorted(json.load(open(sys.argv[1]))):
    print(name)
PY
)
  printf 'SOURCE_METHOD_VOID_RESULT_%s_PASS fixtures=%s compiler=%s\n' "${label//-/_}" "$count" "$compiler"
}

validate_manifest
# All source-oracle cases run before candidate is even resolved or invoked.
run_suite original "$ORIGINAL" original

# empty.cr already defines an Int32 main. Official primitives is the isolated
# prelude for a source-defined Void C entrypoint; no stdlib file is changed.
python3 - "$ABI_SOURCE" <<'PY_ABI_SOURCE'
from pathlib import Path
import hashlib,sys
if hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest() != "62af0f11e3558b6803b95f4f00f5f089c0355664f5c65a03c6cc63c2769fd79d":
    raise SystemExit("C ABI fixture source SHA-256 mismatch")
PY_ABI_SOURCE
if ! run_compiler_safely original "$WORK_DIR/cache-original-abi" "$ORIGINAL" \
    build --prelude=primitives --no-codegen --error-trace "$ABI_SOURCE" \
    >"$WORK_DIR/original-abi.log" 2>&1; then
  cat "$WORK_DIR/original-abi.log" >&2
  exit 1
fi
printf 'PASS original C-ABI Void entrypoint semantic qualification\n'
if [[ "$ORIGINAL_ONLY" == 1 ]]; then
  printf 'SOURCE_METHOD_VOID_RESULT_ORIGINAL_ONLY candidate_not_run=1 fixtures=8\n'
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
run_suite candidate "$CANDIDATE" candidate

if ! run_compiler_safely candidate "$WORK_DIR/cache-candidate-abi" "$CANDIDATE" \
    "$ABI_SOURCE" --no-prelude --emit hir --no-link --no-debug \
    --no-ast-cache --no-llvm-cache -o "$WORK_DIR/abi" \
    >"$WORK_DIR/candidate-abi.log" 2>&1; then
  cat "$WORK_DIR/candidate-abi.log" >&2
  exit 1
fi
python3 - "$WORK_DIR/abi.hir" <<'PY_ABI_HIR'
from pathlib import Path
import re,sys
headers = [x for x in Path(sys.argv[1]).read_text().splitlines() if x.startswith("func @")]
if not any(re.search(r"func @main\(.*\) -> 0(?: |$)", x) for x in headers):
    raise SystemExit("C ABI main did not retain Void: " + repr(headers))
if not any(re.search(r"func @source_discard\(.*\) -> 16(?: |$)", x) for x in headers):
    raise SystemExit("source method did not normalize to Nil: " + repr(headers))
PY_ABI_HIR
printf 'PASS candidate C-ABI Void and source-method Nil HIR boundaries\n'
