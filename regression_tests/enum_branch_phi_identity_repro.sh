#!/usr/bin/env bash
# Preserve nominal enum identity through homogeneous branch merges. PhiFlags::Name
# is 2 and the sink adds 64, so those three branch fixtures expect `B\n`.
# The clean-HEAD 9000 baseline loses enum identity in an unless local join; this script runs the
# pinned original first, then checks the fixed candidate supplied in ADAMAS_BIN.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
FIXTURE_DIR="$ROOT_DIR/regression_tests/enum_branch_phi_identity_fixtures"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"
CRYSTAL_PATH="${CRYSTAL_PATH:-}"

POSITIVE_CASES=(
  direct_enum_value
  local_enum_value
  if_phi_same_enum
  unless_phi_same_enum
  ternary_phi_same_enum
  unless_new_nilable_local
  unless_scalar_unchanged
)
NEGATIVE_CASES=(
  uint8_sink_pointer
  uint8_sink_distinct_enum
  mixed_uint8_phi_into_nominal_sink
  sibling_enum_phi_into_nominal_sink
  local_unless_uint8_phi_into_nominal_sink
  local_unless_sibling_phi_into_nominal_sink
)

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum-branch-phi-identity.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

for name in "${POSITIVE_CASES[@]}"; do
  [[ -f "$FIXTURE_DIR/$name.cr" && -f "$FIXTURE_DIR/$name.expected" ]] || {
    printf 'missing positive fixture: %s\n' "$name" >&2
    exit 2
  }
done
for name in "${NEGATIVE_CASES[@]}"; do
  [[ -f "$FIXTURE_DIR/$name.cr" && -f "$FIXTURE_DIR/$name.reject" ]] || {
    printf 'missing negative fixture: %s\n' "$name" >&2
    exit 2
  }
done

# Exercise all six shared rejection predicates and both stage-specific sibling
# predicates before either compiler. These cases cover union orders, carrier
# erasure, parser-text overlap, wrong sink/type identity, and first-error scope.
python3 - "$FIXTURE_DIR" <<'PY'
from pathlib import Path
import re
import sys

fixtures = Path(sys.argv[1])

def first_error(raw):
    return next((line for line in raw.splitlines() if re.match(rb"^[ \t]*error:", line, re.I)), None)

def is_parser_rejection(line):
    return re.search(rb"syntax error|unexpected token|unterminated|unclosed", line, re.I) is not None

def matches_first_semantic_error(pattern, raw):
    if isinstance(pattern, str):
        pattern = pattern.encode()
    line = first_error(raw)
    return line is not None and not is_parser_rejection(line) and re.search(pattern, line, re.I) is not None

def rejection_pattern(name, stage):
    stage_specific = fixtures / (name + "." + stage + ".reject")
    return (stage_specific if stage_specific.is_file() else fixtures / (name + ".reject")).read_text().strip()

semantic = {
    "uint8_sink_pointer": b"Error: no overload matches sink_byte for argument types (Pointer(UInt8))",
    "uint8_sink_distinct_enum": b"Error: no overload matches sink_byte for argument types (OtherFlags)",
    "mixed_uint8_phi_into_nominal_sink": b"Error: no overload matches sink_flags for argument types (PhiFlags | UInt8)",
    "sibling_enum_phi_into_nominal_sink": b"Error: no overload matches sink_flags for argument types (PhiFlags | OtherFlags)",
    "local_unless_uint8_phi_into_nominal_sink": b"Error: no overload matches sink_flags for argument types (UInt8 | PhiFlags)",
    "local_unless_sibling_phi_into_nominal_sink": b"Error: no overload matches sink_flags for argument types (OtherFlags | PhiFlags)",
}
for name, sample in semantic.items():
    pattern = (fixtures / (name + ".reject")).read_text().strip()
    assert matches_first_semantic_error(pattern, sample), name + ": rejected semantic union form"

typed_semantic = {
    "uint8_sink_pointer": b"Error: expected argument #1 to 'sink_byte' to be UInt8, not Pointer(UInt8)",
    "uint8_sink_distinct_enum": b"Error: expected argument #1 to 'sink_byte' to be UInt8, not OtherFlags",
    "mixed_uint8_phi_into_nominal_sink": b"Error: expected argument #1 to 'sink_flags' to be PhiFlags, not (UInt8 | PhiFlags)",
    "sibling_enum_phi_into_nominal_sink": b"Error: expected argument #1 to 'sink_flags' to be PhiFlags, not (OtherFlags | PhiFlags)",
    "local_unless_uint8_phi_into_nominal_sink": b"Error: expected argument #1 to 'sink_flags' to be PhiFlags, not (PhiFlags | UInt8)",
    "local_unless_sibling_phi_into_nominal_sink": b"Error: expected argument #1 to 'sink_flags' to be PhiFlags, not (PhiFlags | OtherFlags)",
}
for name, sample in typed_semantic.items():
    pattern = (fixtures / (name + ".reject")).read_text().strip()
    assert matches_first_semantic_error(pattern, sample), name + ": rejected typed union form"

union_orders = {
    "mixed_uint8_phi_into_nominal_sink": ("UInt8 | PhiFlags", "PhiFlags | UInt8"),
    "local_unless_uint8_phi_into_nominal_sink": ("UInt8 | PhiFlags", "PhiFlags | UInt8"),
    "sibling_enum_phi_into_nominal_sink": ("OtherFlags | PhiFlags", "PhiFlags | OtherFlags"),
    "local_unless_sibling_phi_into_nominal_sink": ("OtherFlags | PhiFlags", "PhiFlags | OtherFlags"),
}
for name, orders in union_orders.items():
    pattern = (fixtures / (name + ".reject")).read_text().strip()
    for order in orders:
        assert matches_first_semantic_error(pattern, f"Error: no overload matches sink_flags for argument types ({order})".encode()), name + ": no-overload union order"
        assert matches_first_semantic_error(pattern, f"Error: expected argument #1 to 'sink_flags' to be PhiFlags, not ({order})".encode()), name + ": typed union order"

# Historical singleton diagnostics remain valid, but no other type is admitted.
for name, actual_type in (
    ("mixed_uint8_phi_into_nominal_sink", "UInt8"),
    ("local_unless_uint8_phi_into_nominal_sink", "UInt8"),
    ("sibling_enum_phi_into_nominal_sink", "OtherFlags"),
    ("local_unless_sibling_phi_into_nominal_sink", "OtherFlags"),
):
    pattern = (fixtures / (name + ".reject")).read_text().strip()
    assert matches_first_semantic_error(pattern, f"Error: no overload matches sink_flags for argument types ({actual_type})".encode()), name + ": singleton diagnostic"

parser_errors = (
    b"Error: syntax error near UInt8 and Pointer",
    b"Error: syntax error: no overload matches sink_byte for argument types (Pointer(UInt8))",
    b"Error: unexpected token while parsing no overload matches sink_flags for argument types (UInt8)",
    b"Error: unterminated expression after expected argument #1 to 'sink_flags' to be PhiFlags, not OtherFlags",
    b"Error: syntax error: no overload matches sink_flags for argument types (PhiFlags | UInt8)",
    b"Error: syntax error: expected argument #1 to 'sink_flags' to be PhiFlags, not (PhiFlags | OtherFlags)",
)
for name in semantic:
    pattern = (fixtures / (name + ".reject")).read_text().strip()
    for line in parser_errors:
        assert not matches_first_semantic_error(pattern, line), name + ": parser error passed semantic gate"

for name, matching_later_error in semantic.items():
    pattern = (fixtures / (name + ".reject")).read_text().strip()
    raw = b"Error: undefined constant Unrelated\n" + matching_later_error
    assert first_error(raw) == b"Error: undefined constant Unrelated"
    assert not matches_first_semantic_error(pattern, raw), name + ": later error masked first error"

wrong_identity = {
    "uint8_sink_pointer": (b"Error: no overload matches other_sink for argument types (Pointer(UInt8))", b"Error: no overload matches sink_byte for argument types (String)"),
    "uint8_sink_distinct_enum": (b"Error: no overload matches other_sink for argument types (OtherFlags)", b"Error: no overload matches sink_byte for argument types (String)"),
    "mixed_uint8_phi_into_nominal_sink": (b"Error: no overload matches other_sink for argument types (PhiFlags | UInt8)", b"Error: no overload matches sink_flags for argument types (String)", b"Error: no overload matches sink_flags for argument types (PhiFlags | OtherFlags)"),
    "sibling_enum_phi_into_nominal_sink": (b"Error: no overload matches other_sink for argument types (PhiFlags | OtherFlags)", b"Error: no overload matches sink_flags for argument types (String)", b"Error: no overload matches sink_flags for argument types (PhiFlags | UInt8)"),
    "local_unless_uint8_phi_into_nominal_sink": (b"Error: no overload matches other_sink for argument types (UInt8 | PhiFlags)", b"Error: no overload matches sink_flags for argument types (String)", b"Error: no overload matches sink_flags for argument types (OtherFlags | PhiFlags)"),
    "local_unless_sibling_phi_into_nominal_sink": (b"Error: no overload matches other_sink for argument types (OtherFlags | PhiFlags)", b"Error: no overload matches sink_flags for argument types (String)", b"Error: no overload matches sink_flags for argument types (UInt8 | PhiFlags)"),
}
for name, samples in wrong_identity.items():
    pattern = (fixtures / (name + ".reject")).read_text().strip()
    assert all(not matches_first_semantic_error(pattern, line) for line in samples), name + ": accepted wrong sink or incompatible type"

# The original keeps the sibling enum identity in its rejection. The fixed
# candidate can report the UInt8 storage carrier for a heterogeneous enum phi;
# the local-unless sibling case is allowed the same carrier representation.
# Both stages must still reject at sink_flags with an incompatible type.
stage_samples = {
    "sibling_enum_phi_into_nominal_sink": {
        "original": b"Error: no overload matches sink_flags for argument types (OtherFlags)",
        "candidate": b"Error: no overload matches sink_flags for argument types (UInt8)",
    },
    "local_unless_sibling_phi_into_nominal_sink": {
        "original": b"Error: no overload matches sink_flags for argument types (OtherFlags)",
        "candidate": b"Error: expected argument #1 to 'sink_flags' to be PhiFlags, not UInt8",
    },
}
for name, stages in stage_samples.items():
    for stage, diagnostic in stages.items():
        pattern = rejection_pattern(name, stage)
        assert matches_first_semantic_error(pattern, diagnostic), (name, stage, "accepted observed diagnostic")
        for wrong in (
            b"Error: no overload matches other_sink for argument types (UInt8)",
            b"Error: no overload matches sink_flags for argument types (String)",
            b"Error: syntax error: no overload matches sink_flags for argument types (UInt8)",
            b"Error: undefined constant Unrelated\n" + diagnostic,
        ):
            assert not matches_first_semantic_error(pattern, wrong), (name, stage, "accepted wrong sink, type, parser error, or later diagnostic")
    original_pattern = rejection_pattern(name, "original")
    assert not matches_first_semantic_error(original_pattern, b"Error: no overload matches sink_flags for argument types (UInt8)"), name + ": original predicate accepted carrier erasure"
    candidate_pattern = rejection_pattern(name, "candidate")
    assert matches_first_semantic_error(candidate_pattern, b"Error: no overload matches sink_flags for argument types (OtherFlags)"), name + ": candidate lost the preserved enum diagnostic form"

PY

if [[ "${1:-}" == "--self-test" ]]; then
  printf 'PASS[diagnostic-self-test:union orders, staged enum carrier, wrong sink/type, parser errors, and first-error identity]\n'
  exit 0
fi

if [[ ! -x "$SAFE_RUNNER" || ! -x "$ADAMAS_BIN" || ! -x "$CRYSTAL_BIN" || ! -d "$CRYSTAL_PATH" ]]; then
  cat >&2 <<'USAGE'
usage: ADAMAS_BIN=<candidate> CRYSTAL_BIN=<pinned-crystal> CRYSTAL_PATH=<pinned-stdlib> \
  regression_tests/enum_branch_phi_identity_repro.sh
  Add --self-test to run only the pure-Python diagnostic matcher checks.
USAGE
  exit 2
fi

assert_safe_footer() {
  local file="$1"
  local expected_status="$2"
  python3 - "$file" "$expected_status" <<'PY'
from pathlib import Path
import re
import sys

raw = Path(sys.argv[1]).read_bytes()
code = sys.argv[2].encode()
assert re.search(rb"(?m)^\[EXIT: " + code + rb"\] after ~[0-9]+(?:\.[0-9]+)? ?s\r?$", raw), "missing run_safe exit footer"
assert re.search(rb"(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 .*outcome=exit.*reason=exit.*exit_code=" + code + rb"(?:\s|$)", raw), "missing run_safe resource footer"
PY
}

compile_case() {
  local stage="$1"
  local name="$2"
  local fixture="$FIXTURE_DIR/$name.cr"
  local binary="$WORK_DIR/$stage.$name.program"
  local log="$WORK_DIR/$stage.$name.compile.log"
  local cache="$WORK_DIR/cache.$stage.$name"
  local status=0

  rm -f "$binary"
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.$name.compile.resources" \
      "$SAFE_RUNNER" "$CRYSTAL_BIN" 120 4096 build --error-trace --no-debug \
      --prelude=empty "$fixture" -o "$binary" >"$log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_PATH" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.$name.compile.resources" \
      "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 "$fixture" --no-prelude \
      --no-debug --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1 || status=$?
  fi
  rm -rf "$cache"
  printf '%s\n' "$status" >"$WORK_DIR/$stage.$name.compile.status"
}

run_positive() {
  local stage="$1"
  local name="$2"
  local binary="$WORK_DIR/$stage.$name.program"
  local log="$WORK_DIR/$stage.$name.compile.log"
  local status
  compile_case "$stage" "$name"
  status="$(<"$WORK_DIR/$stage.$name.compile.status")"
  if [[ "$status" != 0 || ! -f "$binary" ]]; then
    printf '%s:%s positive compilation failed (exit=%s)\n' "$stage" "$name" "$status" >&2
    cat "$log" >&2
    return 1
  fi
  assert_safe_footer "$log" 0

  local run_status=0
  env RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$stage.$name.run.resources" \
    "$SAFE_RUNNER" "$binary" 5 512 \
    >"$WORK_DIR/$stage.$name.stdout" 2>"$WORK_DIR/$stage.$name.stderr" || run_status=$?
  if [[ "$run_status" != 0 ]]; then
    printf '%s:%s runtime failed (exit=%s)\n' "$stage" "$name" "$run_status" >&2
    cat "$WORK_DIR/$stage.$name.stderr" >&2
    return 1
  fi
  assert_safe_footer "$WORK_DIR/$stage.$name.stderr" 0
  python3 - "$WORK_DIR/$stage.$name.stderr" <<'PY'
from pathlib import Path
import re
import sys

raw = Path(sys.argv[1]).read_bytes()
allowed = (
    re.compile(rb"\[EXIT: 0\] after ~[0-9]+(?:\.[0-9]+)? ?s"),
    re.compile(rb"\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 .*"),
)
unexpected = [line for line in raw.splitlines() if line and not any(p.fullmatch(line) for p in allowed)]
assert not unexpected, "unexpected runtime stderr: " + repr(unexpected)
PY
  if ! cmp -s "$WORK_DIR/$stage.$name.stdout" "$FIXTURE_DIR/$name.expected"; then
    printf '%s:%s stdout mismatch\n' "$stage" "$name" >&2
    printf 'expected: ' >&2
    od -An -t x1 "$FIXTURE_DIR/$name.expected" >&2
    printf 'actual:   ' >&2
    od -An -t x1 "$WORK_DIR/$stage.$name.stdout" >&2
    return 1
  fi
  printf 'PASS[%s:%s]\n' "$stage" "$name"
}

run_negative() {
  local stage="$1"
  local name="$2"
  local binary="$WORK_DIR/$stage.$name.program"
  local log="$WORK_DIR/$stage.$name.compile.log"
  local reject="$FIXTURE_DIR/$name.$stage.reject"
  local status
  [[ -f "$reject" ]] || reject="$FIXTURE_DIR/$name.reject"
  compile_case "$stage" "$name"
  status="$(<"$WORK_DIR/$stage.$name.compile.status")"
  if [[ "$status" != 1 || -e "$binary" ]]; then
    printf '%s:%s expected compiler exit 1 and no binary; got exit=%s\n' "$stage" "$name" "$status" >&2
    cat "$log" >&2
    return 1
  fi
  assert_safe_footer "$log" 1
  python3 - "$log" "$reject" <<'PY'
from pathlib import Path
import re
import sys

raw = Path(sys.argv[1]).read_bytes()
expected = Path(sys.argv[2]).read_text().strip().encode()
primary = next((line for line in raw.splitlines() if re.match(rb"^[ \t]*error:", line, re.I)), None)
assert primary is not None, "missing primary Error diagnostic"
assert re.search(expected, primary, re.I), "primary diagnostic did not match the fixture's semantic predicate: " + repr(primary)
assert not re.search(rb"syntax error|unexpected token|unterminated|unclosed", primary, re.I), "parser rejection is not a semantic result"
PY
  printf 'PASS[%s:%s]\n' "$stage" "$name"
}

run_stage() {
  local stage="$1"
  local name
  for name in "${POSITIVE_CASES[@]}"; do
    run_positive "$stage" "$name"
  done
  for name in "${NEGATIVE_CASES[@]}"; do
    run_negative "$stage" "$name"
  done
}

# Original Crystal must establish the exact behavior before the candidate runs.
run_stage original
printf 'ORIGINAL_PASS_COMPLETE positives=7 negatives=6\n'
run_stage candidate
printf 'CANDIDATE_PASS_COMPLETE positives=7 negatives=6\n'
