#!/usr/bin/env bash
# Regression test (L15): a `when .predicate(arg)` clause with a method name
# ending in `?` and carrying arguments must pass those arguments through.
#
# Bug: emit_case_comparison treated every `?`-suffixed predicate call as a
# zero-argument enum predicate. Its enum-resolution path and its fall-through
# `Call.with_receiver(..., [] of ValueId)` both emitted `subject.method()` with
# an EMPTY arg list, silently dropping `".."` / `'/'`. The call then resolved to
# a no-arg stub (`String#includes?` → "STUB CALLED") or a degraded union-param
# overload (`includes?(Char | String)` reached with an unwrapped String), which
# in the self-hosted (veto) compiler surfaced as a null-base `String#==` —
# a bytesize read at address 4 — inside `Time::Location.load?`'s
# `when .includes?(".."), .starts_with?('/'), .starts_with?('\\')` clause.
# Fix: lower the whole predicate call expression through the normal path so
# argument lowering, overload resolution and String builtin intercepts apply.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/case_pred_args.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

fail=0
# run_case <name> <expected>; the .cr source is read from stdin.
run_case() {
  local name="$1" expect="$2"
  local cr="$TMP_DIR/$name.cr" bin="$TMP_DIR/$name.bin" out="$TMP_DIR/$name.out"
  cat >"$cr"
  if ! "$COMPILER" "$cr" -o "$bin" >"$TMP_DIR/$name.compile" 2>&1; then
    echo "FAIL[$name]: compile error"; cat "$TMP_DIR/$name.compile"; fail=1; return
  fi
  # Read results from STDERR — V2 binaries can truncate the last STDOUT write
  # on normal exit (program-exit-stdio-flush-truncation-bug).
  "$bin" >/dev/null 2>"$out" || true
  local got; got="$(cat "$out")"
  if [[ "$got" == "$expect" ]]; then
    echo "PASS[$name]: [$got]"
  else
    echo "FAIL[$name]: expected [$expect] got [$got]"; fail=1
  fi
}

# Single-predicate `when .includes?(arg)`: the arg must reach String#includes?.
# Was: "STUB CALLED: String#includes?" / abort.
run_case single "other bad" <<'EOF'
def check(name : String)
  case name
  when .includes?("..")
    "bad"
  else
    "other"
  end
end
STDERR.print("#{check("a/b")} #{check("../x")}")
EOF

# Multi-predicate clause mirroring Time::Location.load? — each predicate keeps
# its argument (a String for includes?, a Char for starts_with?).
run_case multi "other bad bad special" <<'EOF'
def classify(name : String)
  case name
  when "", "UTC", "Etc/UTC"
    "special"
  when .includes?(".."), .starts_with?('/'), .starts_with?('\\')
    "bad"
  else
    "other"
  end
end
STDERR.print("#{classify("a/b")} #{classify("../x")} #{classify("/abs")} #{classify("UTC")}")
EOF

if [[ "$fail" -ne 0 ]]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
