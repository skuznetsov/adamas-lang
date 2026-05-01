#!/usr/bin/env bash
# No-prelude guard: accessor visibility must survive parser -> HIR.
# Private accessors reject explicit non-self receivers. Protected accessors
# follow the same namespace rule as protected methods.
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
PROTECTED_PASS_SRC="$TMP_DIR/protected_accessor_pass.cr"
PROTECTED_FAIL_SRC="$TMP_DIR/protected_accessor_fail.cr"
PASS_OUT="$TMP_DIR/private_accessor_pass"
FAIL_OUT="$TMP_DIR/private_accessor_fail"
PROTECTED_PASS_OUT="$TMP_DIR/protected_accessor_pass"
PROTECTED_FAIL_OUT="$TMP_DIR/protected_accessor_fail"
PASS_LOG="$TMP_DIR/pass.log"
FAIL_LOG="$TMP_DIR/fail.log"
PROTECTED_PASS_LOG="$TMP_DIR/protected_pass.log"
PROTECTED_FAIL_LOG="$TMP_DIR/protected_fail.log"

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

cat >"$PROTECTED_PASS_SRC" <<'CR'
class Object
end

class Vault
  protected property code : Int32

  def initialize(@code : Int32)
  end

  class Auditor
    def initialize(@vault : Vault)
    end

    def read : Int32
      @vault.code
    end
  end
end

Vault::Auditor.new(Vault.new(7)).read
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
  "$PROTECTED_PASS_SRC" --no-prelude --emit hir --no-link -o "$PROTECTED_PASS_OUT" >"$PROTECTED_PASS_LOG" 2>&1

cat >"$PROTECTED_FAIL_SRC" <<'CR'
class Object
end

class Vault
  protected property code : Int32

  def initialize(@code : Int32)
  end
end

class Stranger
  def read(vault : Vault) : Int32
    vault.code
  end
end

Stranger.new.read(Vault.new(7))
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 1024 \
  "$PROTECTED_FAIL_SRC" --no-prelude --emit hir --no-link -o "$PROTECTED_FAIL_OUT" >"$PROTECTED_FAIL_LOG" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "p2 visibility regression: unrelated protected accessor call compiled" >&2
  cat "$PROTECTED_FAIL_LOG" >&2
  exit 1
fi

if ! grep -Eq "protected method 'code' called for Vault" "$PROTECTED_FAIL_LOG"; then
  echo "p2 visibility regression: expected protected accessor diagnostic missing" >&2
  cat "$PROTECTED_FAIL_LOG" >&2
  exit 1
fi

echo "p2_visibility_private_accessor_no_prelude_ok"
