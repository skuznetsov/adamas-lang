#!/usr/bin/env bash
# Original-first, no-prelude source identity checks for explicit Array(T) roots.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -n "${ADAMAS_ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "$ADAMAS_ROOT_DIR" && pwd -P)"
elif [[ -x "$SCRIPT_DIR/../scripts/run_safe.sh" ]]; then
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
else
  ROOT_DIR="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$ROOT_DIR" ]]; then
  echo "set ADAMAS_ROOT_DIR when running this bundle outside the Adamas checkout" >&2
  exit 2
fi

SAFE_RUNNER="${ADAMAS_SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
COMPILER="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal 2>/dev/null || true)}}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/array_source_type_identity"
CASES_FILE="$FIXTURE_DIR/cases.json"
FIXTURE_HASHES="$FIXTURE_DIR/SHA256SUMS"

if [[ "$ORIGINAL_ONLY" != 0 && "$ORIGINAL_ONLY" != 1 ]]; then
  echo "ORIGINAL_ONLY must be 0 or 1" >&2
  exit 2
fi
if [[ ! -x "$SAFE_RUNNER" ]]; then
  echo "safe runner is unavailable: $SAFE_RUNNER" >&2
  exit 2
fi
if [[ -z "$ORIGINAL" || ! -x "$ORIGINAL" ]]; then
  echo "set ORIGINAL_CRYSTAL_BIN or ORIGINAL_CRYSTAL to executable Crystal 1.22.1" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != 1 && ! -x "$COMPILER" ]]; then
  echo "candidate compiler is unavailable: $COMPILER" >&2
  exit 2
fi

sha256_file() {
  local path="$1"
  local line
  if command -v sha256sum >/dev/null 2>&1; then
    line="$(sha256sum "$path")" || return
  elif command -v shasum >/dev/null 2>&1; then
    line="$(shasum -a 256 "$path")" || return
  else
    echo "sha256sum or shasum is required to verify fixture bytes" >&2
    return 2
  fi
  printf '%s\n' "${line%% *}"
}

[[ -f "$CASES_FILE" && -f "$FIXTURE_HASHES" ]] || {
  echo "case or fixture hash manifest is missing" >&2
  exit 2
}
while read -r expected_hash filename; do
  [[ -n "$expected_hash" && -n "$filename" && -f "$FIXTURE_DIR/$filename" ]] || {
    echo "invalid fixture hash manifest entry: $filename" >&2
    exit 2
  }
  actual_hash="$(sha256_file "$FIXTURE_DIR/$filename")"
  [[ "$actual_hash" == "$expected_hash" ]] || {
    echo "fixture hash mismatch: $filename" >&2
    exit 2
  }
done < "$FIXTURE_HASHES"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/array-source-type-identity.XXXXXX")"
mkdir -p "$WORK_DIR/tmp" "$WORK_DIR/home" "$WORK_DIR/cache"
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

clean_env() {
  env -i PATH="${PATH:-/usr/bin:/bin}" HOME="$WORK_DIR/home" \
    TMPDIR="$WORK_DIR/tmp" LANG=C LC_ALL=C "$@"
}

clean_compile_env() {
  local -a link_environment=()
  [[ -n "${LIBRARY_PATH:-}" ]] && link_environment+=("LIBRARY_PATH=$LIBRARY_PATH")
  [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]] && \
    link_environment+=("ADAMAS_EXTRA_LINK_FLAGS=$ADAMAS_EXTRA_LINK_FLAGS")
  clean_env "${link_environment[@]}" "$@"
}

CRYSTAL_STDLIB="${ORIGINAL_CRYSTAL_PATH:-}"
if [[ -z "$CRYSTAL_STDLIB" ]]; then
  if ! clean_env RUN_SAFE_PASSTHROUGH_STDIO=1 \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/crystal-env.resources" \
      "$SAFE_RUNNER" "$ORIGINAL" 20 512 env CRYSTAL_PATH \
      >"$WORK_DIR/crystal-path.out" 2>"$WORK_DIR/crystal-path.log"; then
    echo "could not read installed Crystal's CRYSTAL_PATH" >&2
    cat "$WORK_DIR/crystal-path.log" >&2
    exit 2
  fi
  CRYSTAL_STDLIB="$(tr -d '\r\n' < "$WORK_DIR/crystal-path.out")"
fi
stdlib_found=0
IFS=: read -r -a stdlib_paths <<<"$CRYSTAL_STDLIB"
for stdlib_path in "${stdlib_paths[@]}"; do
  [[ -d "$stdlib_path" ]] && stdlib_found=1
done
[[ "$stdlib_found" == 1 ]] || {
  echo "Crystal 1.22.1 CRYSTAL_PATH has no existing source directory: $CRYSTAL_STDLIB" >&2
  exit 2
}

# The JSON array drives every case, so adding controls does not require editing
# a second list in this runner. Hex stdout keeps records newline-safe.
CASE_TABLE="$WORK_DIR/cases.tsv"
python3 - "$CASES_FILE" "$SCRIPT_DIR" "$CASE_TABLE" <<'PY'
import hashlib
import json
import pathlib
import sys

cases_path = pathlib.Path(sys.argv[1])
script_dir = pathlib.Path(sys.argv[2])
out_path = pathlib.Path(sys.argv[3])
cases = json.loads(cases_path.read_text())
if not isinstance(cases, list) or not cases:
    raise SystemExit("cases.json must be a non-empty array")
rows = []
seen = set()
for case in cases:
    name = case["name"]
    source = case["source"]
    if name in seen or "\t" in name or "\n" in name:
        raise SystemExit(f"duplicate or invalid case name: {name!r}")
    seen.add(name)
    relative = pathlib.PurePosixPath(source)
    if relative.is_absolute() or ".." in relative.parts:
        raise SystemExit(f"source path must be relative and stay in the bundle: {source}")
    source_path = script_dir.joinpath(*relative.parts)
    digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
    if digest != case["source_sha256"]:
        raise SystemExit(f"source_sha256 mismatch for {source}")
    expected = case.get("expected_stdout", "").encode().hex() or "-"
    if case["ok"]:
        stock_diag = candidate_diag = "-"
    else:
        stock_diag = case["stock_diagnostic"]
        candidate_diag = case["candidate_diagnostic"]
        if any("\t" in value or "\n" in value for value in (stock_diag, candidate_diag)):
            raise SystemExit(f"diagnostic contains a record separator: {name}")
    rows.append("\t".join((name, "1" if case["ok"] else "0", source,
                             expected, stock_diag, candidate_diag)))
out_path.write_text("\n".join(rows) + "\n")
PY

compile_case() {
  local stage="$1"
  local compiler="$2"
  local name="$3"
  local ok="$4"
  local source_rel="$5"
  local expected_hex="$6"
  local stock_diag="$7"
  local candidate_diag="$8"
  local source="$SCRIPT_DIR/$source_rel"
  local binary="$WORK_DIR/$stage-$name.bin"
  local cache="$WORK_DIR/cache/$stage-$name"
  local log="$WORK_DIR/$stage-$name.compile.log"
  local status=0
  local -a stock_link_flags=()
  mkdir -p "$cache"
  [[ -n "${ORIGINAL_CRYSTAL_LINK_FLAGS:-}" ]] && \
    stock_link_flags=(--link-flags "$ORIGINAL_CRYSTAL_LINK_FLAGS")

  if [[ "$stage" == original ]]; then
    if clean_compile_env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.compile.resources" \
        "$SAFE_RUNNER" "$compiler" 180 8192 build --prelude=empty \
        "${stock_link_flags[@]}" "$source" -o "$binary" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if clean_compile_env CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.compile.resources" \
        "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-prelude \
        --no-ast-cache --no-llvm-cache --no-debug -o "$binary" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi

  if [[ "$ok" == 1 ]]; then
    if [[ "$status" != 0 || ! -x "$binary" ]]; then
      printf 'FAIL %s positive %s (compile status %s)\n' "$stage" "$name" "$status" >&2
      cat "$log" >&2
      return 1
    fi
    local expected_file="$WORK_DIR/$stage-$name.expected"
    local stdout="$WORK_DIR/$stage-$name.stdout"
    local run_log="$WORK_DIR/$stage-$name.run.log"
    python3 - "$expected_hex" "$expected_file" <<'PY'
import pathlib
import sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(sys.argv[1]))
PY
    if ! clean_env RUN_SAFE_PASSTHROUGH_STDIO=1 \
        RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage-$name.run.resources" \
        "$SAFE_RUNNER" "$binary" 15 512 >"$stdout" 2>"$run_log"; then
      printf 'FAIL %s positive %s (run)\n' "$stage" "$name" >&2
      cat "$run_log" >&2
      return 1
    fi
    if ! cmp -s "$expected_file" "$stdout"; then
      printf 'FAIL %s positive %s (stdout bytes differ)\n' "$stage" "$name" >&2
      od -An -tx1c "$stdout" >&2
      cat "$run_log" >&2
      return 1
    fi
    printf 'PASS %s positive %s\n' "$stage" "$name"
    return 0
  fi

  local expected_diag="$stock_diag"
  [[ "$stage" == candidate ]] && expected_diag="$candidate_diag"
  local diagnostic_count
  diagnostic_count="$(grep -Ec '^(error:|Error:)' "$log" || true)"
  if [[ "$status" != 1 || -e "$binary" || "$diagnostic_count" != 1 ]] || \
      ! grep -Fq "$expected_diag" "$log" || ! grep -Fq '[EXIT: 1]' "$log"; then
    printf 'FAIL %s negative %s (expected exit 1, no executable, and scoped diagnostic)\n' \
      "$stage" "$name" >&2
    cat "$log" >&2
    return 1
  fi
  printf 'PASS %s negative %s\n' "$stage" "$name"
}

run_stage() {
  local stage="$1"
  local compiler="$2"
  local name ok source expected stock_diag candidate_diag
  while IFS=$'\t' read -r name ok source expected stock_diag candidate_diag; do
    compile_case "$stage" "$compiler" "$name" "$ok" "$source" \
      "$expected" "$stock_diag" "$candidate_diag"
  done < "$CASE_TABLE"
}

run_stage original "$ORIGINAL"
if [[ "$ORIGINAL_ONLY" == 1 ]]; then
  printf 'PASS original-only array source identity cases\n'
  exit 0
fi
run_stage candidate "$COMPILER"
printf 'PASS array source identity contract cases\n'
