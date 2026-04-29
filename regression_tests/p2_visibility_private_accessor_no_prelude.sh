#!/usr/bin/env bash
# No-prelude guard: private accessor visibility must survive parser -> HIR and
# reject explicit non-self receivers. Bare/self calls from the owner remain valid.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_visibility_private_accessor_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_SRC="$TMP_DIR/private_accessor_pass.cr"
FAIL_SRC="$TMP_DIR/private_accessor_fail.cr"
PASS_OUT="$TMP_DIR/private_accessor_pass"
FAIL_OUT="$TMP_DIR/private_accessor_fail"
PASS_LOG="$TMP_DIR/pass.log"
FAIL_LOG="$TMP_DIR/fail.log"

cat >"$PASS_SRC" <<'CR'
class Object
end

class SecretBox
  private getter secret : Int32

  def initialize(@secret : Int32)
  end

  def own
    secret
  end
end

SecretBox.new(1).own
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
  "$PASS_SRC" --no-prelude --emit hir --no-link -o "$PASS_OUT" >"$PASS_LOG" 2>&1

cat >"$FAIL_SRC" <<'CR'
class Object
end

class SecretBox
  private getter secret : Int32

  def initialize(@secret : Int32)
  end

  def leak(other : SecretBox)
    other.secret
  end
end

SecretBox.new(1).leak(SecretBox.new(2))
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
  "$FAIL_SRC" --no-prelude --emit hir --no-link -o "$FAIL_OUT" >"$FAIL_LOG" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "p2 visibility regression: explicit non-self private getter call compiled" >&2
  cat "$FAIL_LOG" >&2
  exit 1
fi

if ! grep -Eq "private method 'secret' called for SecretBox" "$FAIL_LOG"; then
  echo "p2 visibility regression: expected private getter diagnostic missing" >&2
  cat "$FAIL_LOG" >&2
  exit 1
fi

echo "p2_visibility_private_accessor_no_prelude_ok"
