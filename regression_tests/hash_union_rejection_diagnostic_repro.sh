#!/usr/bin/env bash
# A rejected union hash ABI must report both branch contracts without crashing.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_union_diagnostic.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/rejected.cr" <<'CR'
module Crystal
  struct Hasher
  end
end
struct Nil
  def hash(hasher : Crystal::Hasher) : Crystal::Hasher
    hasher
  end
end
struct Tuple
  def hash(hasher : Crystal::Hasher) : String
    "custom"
  end
end
def append_hash(value : Nil | Tuple(String, Int32), hasher : Crystal::Hasher)
  value.hash(hasher)
end
def choose(flag : Bool) : Nil | Tuple(String, Int32)
  flag ? nil : {"x", 1}
end
append_hash(choose(true), Crystal::Hasher.new)
CR
set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
  "$WORK_DIR/rejected.cr" --no-prelude -o "$WORK_DIR/rejected" >"$WORK_DIR/rejected.log" 2>&1
status=$?
set -e
if [[ "$status" != 1 ]] ||
   ! LC_ALL=C grep -aFq 'cannot safely lower heterogeneous hash returns for union Nil | Tuple(String, Int32)' "$WORK_DIR/rejected.log" ||
   ! LC_ALL=C grep -aFq 'Nil -> Nil#hash$Crystal::Hasher: Crystal::Hasher' "$WORK_DIR/rejected.log" ||
   ! LC_ALL=C grep -aFq 'Tuple(String, Int32) -> Tuple(String, Int32)#hash$Crystal::Hasher: String' "$WORK_DIR/rejected.log"; then
  cat "$WORK_DIR/rejected.log" >&2
  exit 1
fi
sed -e 's/) : String/) : Crystal::Hasher/' -e 's/"custom"/hasher/' \
  "$WORK_DIR/rejected.cr" >"$WORK_DIR/admitted.cr"
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 4096 \
  "$WORK_DIR/admitted.cr" --no-prelude -o "$WORK_DIR/admitted" >"$WORK_DIR/admitted.log" 2>&1; then
  cat "$WORK_DIR/admitted.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/admitted" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo hash_union_rejection_diagnostic_repro_ok
