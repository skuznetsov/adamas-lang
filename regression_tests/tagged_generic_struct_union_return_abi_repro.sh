#!/usr/bin/env bash
# Runtime oracle for instance-dependent returns dispatched through a tagged
# union of concrete Hash::Entry structs. Hash::Entry uses InlineAddress storage,
# so this also guards specialization-dependent hash/key/value offsets.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tagged_generic_struct_union_return.XXXXXX")"

cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"

cat >"$SRC" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

alias EntryUnion = Hash::Entry(String, Nil | String) | Hash::Entry(String, Nil) | Hash::Entry(String, String)

class Hash(K, V)
  def first_entry_for_union_oracle : Entry(K, V)
    @entries[@first]
  end
end

def stored_mixed_entry
  table = Hash(String, Nil | String).new
  table["mixed"] = "mixed-value"
  table.first_entry_for_union_oracle
end

def stored_nil_entry
  table = Hash(String, Nil).new
  table["nil"] = nil
  table.first_entry_for_union_oracle
end

def stored_string_entry
  table = Hash(String, String).new
  table["string"] = "string-value"
  table.first_entry_for_union_oracle
end

def choose_entry(kind : Int32) : EntryUnion
  case kind
  when 0
    stored_mixed_entry
  when 1
    stored_nil_entry
  else
    stored_string_entry
  end
end

def entry_value(entry : EntryUnion)
  entry.value
end

mixed_entry = choose_entry(0)
mixed = entry_value(mixed_entry)
mixed_ok = case mixed
           when String
             mixed == "mixed-value" && mixed_entry.key == "mixed" && !mixed_entry.deleted?
           when Nil
             false
           end

nil_entry = choose_entry(1)
nil_value = entry_value(nil_entry)
nil_ok = nil_value.nil? && nil_entry.key == "nil" && !nil_entry.deleted?

string_entry = choose_entry(2)
string = entry_value(string_entry)
string_ok = case string
            when String
              string == "string-value" && string_entry.key == "string" && !string_entry.deleted?
            when Nil
              false
            end

if mixed_ok && nil_ok && string_ok
  LibC.printf("OK\n")
else
  LibC.printf("BAD\n")
end
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 4096 "$SRC" -o "$OUT" >"$TMP_DIR/compile.log" 2>&1; then
  echo "FAIL: compile error" >&2
  tail -20 "$TMP_DIR/compile.log" >&2
  exit 1
fi

RAW="$("$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 2>/dev/null)"
GOT="$(printf '%s\n' "$RAW" | sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/p' | sed '1d;$d')"

if [[ "$GOT" != "OK" ]]; then
  echo "FAIL: tagged generic struct union return ABI (expected 'OK', got '$GOT')" >&2
  exit 1
fi

echo "PASS: Hash::Entry tagged-union return ABI preserves hash/key/value storage"
