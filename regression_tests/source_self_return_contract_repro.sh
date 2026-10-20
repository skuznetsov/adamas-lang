#!/usr/bin/env bash
# Original-first compile-only checks for exact :self return admission and
# inherited runtime receiver, lexical owner, and materialization-cache identity.
set -euo pipefail

ROOT_DIR="$(cd "${ADAMAS_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd -P)"
PACKET="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures/source_self_return_contract" && pwd -P)"
CANDIDATE="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_HINT="${ORIGINAL_CRYSTAL_BIN:-crystal}"
if [[ "$ORIGINAL_HINT" == */* ]]; then
  ORIGINAL="$ORIGINAL_HINT"
else
  ORIGINAL="$(command -v "$ORIGINAL_HINT" || true)"
fi
SAFE_RUN="${ADAMAS_RUN_SAFE:-$ROOT_DIR/scripts/run_safe.sh}"
[[ -x "$CANDIDATE" && -x "$ORIGINAL" && -x "$SAFE_RUN" ]] || exit 2
WORK="$(mktemp -d "${TMPDIR:-/tmp}/adamas-self-return-contract.XXXXXX")"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-90}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-8192}"
ORIGINAL_LINK_ARGS=()
if [[ "$(uname -s)" == Darwin ]]; then
  ORIGINAL_LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

check_footer() {
  python3 - "$1" "$2" <<'PY_FOOTER'
from pathlib import Path
import re, sys
raw = Path(sys.argv[1]).read_bytes()
code = sys.argv[2].encode()
resource = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
assert resource, "missing run_safe resource footer"
assert all(value in resource.group(0) for value in (
    b"outcome=exit", b"reason=exit", b"exit_code=" + code,
)), "unexpected run_safe outcome"
assert re.search(rb'(?m)^\[EXIT: ' + code + rb'\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\Z',
                 raw[:resource.start()]), "missing run_safe exit footer"
PY_FOOTER
}

run_one() {
  local stage="$1" name="$2" compiler output log code=0
  compiler="$ORIGINAL"
  [[ "$stage" == original ]] || compiler="$CANDIDATE"
  output="$WORK/$stage.$name.bin"
  log="$WORK/$stage.$name.compile.log"
  mkdir -p "$WORK/cache.$stage.$name"

  if [[ "$stage" == original ]]; then
    if CRYSTAL_CACHE_DIR="$WORK/cache.$stage.$name" \
      "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" build --no-debug --prelude=empty \
      "${ORIGINAL_LINK_ARGS[@]}" \
      "$PACKET/$name.cr" -o "$output" >"$log" 2>&1; then
      :
    else
      code=$?
    fi
  else
    if CRYSTAL_CACHE_DIR="$WORK/cache.$stage.$name" ADAMAS_LLVM_CACHE=0 \
      "$SAFE_RUN" "$compiler" "$COMPILE_TIMEOUT_SEC" "$COMPILE_MAX_MEM_MB" \
      "$PACKET/$name.cr" --no-prelude --no-debug --no-ast-cache --no-llvm-cache \
      -o "$output" >"$log" 2>&1; then
      :
    else
      code=$?
    fi
  fi

  if [[ "$name" == *_negative ]]; then
    if [[ "$code" != 1 || -e "$output" ]] || ! check_footer "$log" 1; then
      cat "$log" >&2
      return 1
    fi
    if ! python3 - "$PACKET" "$log" "$name" <<'PY_NEGATIVE'
from pathlib import Path
import json, sys
packet = Path(sys.argv[1])
text = Path(sys.argv[2]).read_text(errors="replace")
name = sys.argv[3]
expected = json.loads((packet / "negative_diagnostics.json").read_text())[name]
lower = text.lower()
assert any(fragment in lower for fragment in (
    "must return", "return type", "expected argument", "no overload matches",
    "can't restrict", "cannot restrict", "expected to",
)), "rejection is not a semantic return/type error"
for fragment in expected:
    assert fragment.lower() in lower, f"missing diagnostic identity {fragment!r}"
PY_NEGATIVE
    then
      cat "$log" >&2
      return 1
    fi
    return 0
  fi

  if [[ "$code" != 0 || ! -x "$output" ]] || ! check_footer "$log" 0; then
    cat "$log" >&2
    return 1
  fi

  # Compile-only admission check: the produced executable is intentionally never run.
  return 0
}

qualify_stage() {
  local stage="$1" name failed=0
  for name in implicit_positive explicit_positive descendant_positive descendant_union_positive nested_helper_context_positive noreturn_branch_positive runtime_receiver_positive warm_sibling_receiver_positive lexical_owner_positive generic_parent_receiver_positive; do
    if run_one "$stage" "$name"; then
      printf 'PASS[%s:%s]\n' "$stage" "$name"
    else
      printf 'FAIL[%s:%s]\n' "$stage" "$name" >&2
      failed=1
    fi
  done
  for name in implicit_other_negative explicit_other_negative implicit_nil_negative explicit_nil_negative type_value_negative other_union_negative nil_union_negative bare_return_negative early_bad_return_negative zero_arity_unrelated_negative; do
    if run_one "$stage" "$name"; then
      printf 'PASS[%s:%s]\n' "$stage" "$name"
    else
      printf 'FAIL[%s:%s]\n' "$stage" "$name" >&2
      failed=1
    fi
  done
  return "$failed"
}

qualify_stage original
qualify_stage candidate
