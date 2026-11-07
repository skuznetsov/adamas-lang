#!/usr/bin/env bash
# Preserve macro double-splat source entries, separators, and diagnostics.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKET_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_ROOT="$SCRIPT_DIR/fixtures/macro_double_splat_contract"
MANIFEST="$FIXTURE_ROOT/cases.json"

if [[ -n "${ADAMAS_ROOT_DIR:-${ADAMAS_ROOT:-}}" ]]; then
  ADAMAS_ROOT="$(cd "${ADAMAS_ROOT_DIR:-$ADAMAS_ROOT}" && pwd)"
else
  search_dir="$PACKET_ROOT"
  ADAMAS_ROOT=""
  while [[ "$search_dir" != / ]]; do
    if [[ -x "$search_dir/scripts/run_safe.sh" ]]; then
      ADAMAS_ROOT="$search_dir"
      break
    fi
    search_dir="$(dirname "$search_dir")"
  done
  if [[ -z "$ADAMAS_ROOT" ]] && git -C "$PWD" rev-parse --show-toplevel >/dev/null 2>&1; then
    ADAMAS_ROOT="$(git -C "$PWD" rev-parse --show-toplevel)"
  fi
  [[ -n "$ADAMAS_ROOT" ]] || { echo 'set ADAMAS_ROOT_DIR to the Adamas checkout containing scripts/run_safe.sh' >&2; exit 2; }
fi
SAFE="${ADAMAS_SAFE_RUNNER:-${ADAMAS_RUN_SAFE:-$ADAMAS_ROOT/scripts/run_safe.sh}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
[[ -x "$SAFE" && -x "$ORIGINAL" ]] || { echo 'safe runner and original Crystal must be executable' >&2; exit 2; }

case "${1:-}" in
  --original-only) [[ "$#" -eq 1 ]] || exit 2; CANDIDATE="" ;;
  --candidate) [[ "$#" -eq 2 && -n "$2" ]] || exit 2; CANDIDATE="$2" ;;
  "") CANDIDATE="${ADAMAS_BIN:-$ADAMAS_ROOT/bin/adamas}" ;;
  *) [[ "$#" -eq 1 ]] || exit 2; CANDIDATE="$1" ;;
esac
[[ -z "$CANDIDATE" || -x "$CANDIDATE" ]] || { echo "candidate is not executable: $CANDIDATE" >&2; exit 2; }

BASE_PATH="${PATH:-/usr/bin:/bin}"
BASE_HOME="${HOME:-/tmp}"
BASE_TMP="${TMPDIR:-/tmp}"
PRISTINE_CRYSTAL_PATH="${PRISTINE_CRYSTAL_PATH:-${CRYSTAL_PATH:-}}"
if [[ -z "$PRISTINE_CRYSTAL_PATH" ]]; then
  PRISTINE_CRYSTAL_PATH="$(env -i "PATH=$BASE_PATH" "HOME=$BASE_HOME" "TMPDIR=$BASE_TMP" \
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$ORIGINAL" 10 512 env CRYSTAL_PATH)"
fi
[[ -d "$PRISTINE_CRYSTAL_PATH" ]] || { echo 'could not resolve original Crystal CRYSTAL_PATH' >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/macro-double-splat.XXXXXX")"
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

python3 - "$MANIFEST" "$FIXTURE_ROOT" "$WORK/cases.tsv" <<'PY_CASES'
from pathlib import Path
import hashlib, json, sys
manifest_path, packet_root, out_path = map(Path, sys.argv[1:])
manifest = json.loads(manifest_path.read_text())
cases = manifest.get('cases', [])
if len(cases) != manifest.get('case_count') or not cases:
    raise SystemExit(f'unexpected case count: {len(cases)}')
rows = []
for case in cases:
    source = packet_root / case['source']
    if not source.is_file():
        raise SystemExit(f'missing source: {source}')
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != case['source_sha256']:
        raise SystemExit(f'source hash mismatch: {case["name"]}')
    expected_hex = case.get('expected', '').encode().hex()
    fields = [
        case['name'], str(source), '1' if case['ok'] else '0', expected_hex,
        case.get('original_diagnostic', ''),
        case.get('original_diagnostic_regex', ''),
        case.get('candidate_diagnostic_regex', ''),
    ]
    if any('\x1f' in field or '\n' in field for field in fields):
        raise SystemExit(f'separator/newline not supported in manifest field: {case["name"]}')
    rows.append('\x1f'.join(fields))
out_path.write_text('\n'.join(rows) + '\n')
PY_CASES

compile_source() {
  local stage="$1" source="$2" output="$3" log="$4" status
  local -a clean=(env -i "PATH=$BASE_PATH" "HOME=$BASE_HOME" "TMPDIR=$BASE_TMP"
    "CRYSTAL_PATH=$PRISTINE_CRYSTAL_PATH" RUN_SAFE_PASSTHROUGH_STDIO=1)
  local key value
  for key in SDKROOT DEVELOPER_DIR LIBRARY_PATH CPATH DYLD_LIBRARY_PATH LD_LIBRARY_PATH; do
    value="${!key-}"
    [[ -z "$value" ]] || clean+=("$key=$value")
  done
  if [[ "$stage" == original ]]; then
    local -a args=(build "$source" --prelude=empty --no-debug -o "$output")
    [[ "$(uname -s)" != Darwin ]] || args+=(--link-flags=-fuse-ld=/usr/bin/ld)
    "${clean[@]}" CRYSTAL_CACHE_DIR="$WORK/original.cache" \
      "$SAFE" "$ORIGINAL" 180 8192 "${args[@]}" >"$log" 2>&1
  else
    "${clean[@]}" CRYSTAL_CACHE_DIR="$WORK/candidate.cache" ADAMAS_LLVM_CACHE=0 \
      "ADAMAS_EXTRA_LINK_FLAGS=${ADAMAS_EXTRA_LINK_FLAGS:-}" \
      "$SAFE" "$CANDIDATE" 180 8192 "$source" \
      --no-ast-cache --no-llvm-cache --no-debug --no-prelude -o "$output" >"$log" 2>&1
  fi
}

run_positive() {
  local stage="$1" name="$2" source="$3" expected_hex="$4"
  local output="$WORK/$stage.$name.bin" log="$WORK/$stage.$name.compile.log"
  local stdout="$WORK/$stage.$name.stdout" stderr="$WORK/$stage.$name.stderr"
  local runner_log="$WORK/$stage.$name.runner.log" expected="$WORK/$name.expected"
  if ! compile_source "$stage" "$source" "$output" "$log"; then
    echo "FAIL: $stage rejected positive $name" >&2; tail -60 "$log" >&2; return 1
  fi
  if ! env -i "PATH=$BASE_PATH" "HOME=$BASE_HOME" "TMPDIR=$BASE_TMP" \
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/run_program" 15 1024 \
    "$output" "$stderr" >"$stdout" 2>"$runner_log"; then
    echo "FAIL: $stage positive executable failed: $name" >&2
    cat "$stderr" "$runner_log" >&2
    return 1
  fi
  python3 - "$expected_hex" "$expected" <<'PY_EXPECTED'
from pathlib import Path
import sys
Path(sys.argv[2]).write_bytes(bytes.fromhex(sys.argv[1]))
PY_EXPECTED
  if ! cmp -s "$expected" "$stdout" || [[ -s "$stderr" ]]; then
    echo "FAIL: $stage output differs for $name" >&2
    od -An -tx1c "$stdout" >&2
    [[ ! -s "$stderr" ]] || cat "$stderr" >&2
    return 1
  fi
}

expect_rejection() {
  local stage="$1" name="$2" source="$3" original_diag="$4"
  local original_regex="$5" candidate_regex="$6"
  local output="$WORK/$stage.$name.bin" log="$WORK/$stage.$name.compile.log" status=0 pattern
  compile_source "$stage" "$source" "$output" "$log" || status=$?
  if [[ "$status" -ne 1 || -e "$output" ]]; then
    echo "FAIL: $stage must reject $name with rc=1 and no executable, got $status" >&2
    tail -60 "$log" >&2
    return 1
  fi
  if grep -Eiq 'Internal compiler error|Unhandled exception|Segmentation fault|panic:' "$log"; then
    echo "FAIL: $stage rejected $name through a compiler failure" >&2
    tail -60 "$log" >&2
    return 1
  fi
  if [[ "$stage" == original ]]; then
    if [[ -n "$original_diag" ]]; then
      grep -Fq "$original_diag" "$log" || {
        echo "FAIL: original diagnostic identity differs for $name" >&2; tail -60 "$log" >&2; return 1;
      }
    elif [[ -n "$original_regex" ]]; then
      grep -Eq "$original_regex" "$log" || {
        echo "FAIL: original diagnostic category differs for $name" >&2; tail -60 "$log" >&2; return 1;
      }
    else
      echo "FAIL: missing original diagnostic oracle for $name" >&2; return 1
    fi
  else
    pattern="$candidate_regex"
    [[ -n "$pattern" ]] || pattern="$original_regex"
    [[ -n "$pattern" ]] || pattern="$original_diag"
    grep -Eq "$pattern" "$log" || {
      echo "FAIL: candidate diagnostic category differs for $name" >&2; tail -60 "$log" >&2; return 1;
    }
  fi
}

run_stage() {
  local stage="$1" name source ok expected_hex original_diag original_regex candidate_regex
  while IFS=$'\x1f' read -r name source ok expected_hex original_diag original_regex candidate_regex; do
    [[ -n "$name" ]] || continue
    if [[ "$ok" == 1 ]]; then
      run_positive "$stage" "$name" "$source" "$expected_hex"
    else
      expect_rejection "$stage" "$name" "$source" "$original_diag" "$original_regex" "$candidate_regex"
    fi
  done <"$WORK/cases.tsv"
}

run_stage original
[[ -z "$CANDIDATE" ]] || run_stage candidate
echo 'PASS: original-first macro double-splat source, suffix, and rejection contracts'
