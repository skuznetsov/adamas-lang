#!/usr/bin/env bash
# Regression test: a generic `.new` written with an absolute path receiver
# (`::Hash(K, V).new`) must resolve its type arguments in the current scope, so a
# bare nested type name is qualified to its FQ form at the instantiation site.
#
# Bug: the `.new`-on-type-like-Call branch in lower_member_access built its
# type_args via only substitute_type_params_in_type_name + normalize_tuple_..,
# MISSING the resolve_type_name_in_context step that the Generic-receiver branch
# performs. So a bare `TypeRef` (an ambiguous nested type: both Adamas::HIR::TypeRef
# and Adamas::MIR::TypeRef exist) stayed unqualified and leaked into Hash
# monomorphization, where it was re-resolved against foreign scopes (Hash,
# Reference, Crystal::Hasher, Enumerable, ...) into a PHANTOM name like
# `Hash::TypeRef`. The phantom type's methods are never materialized, so a later
# `h[k] = v` reached "STUB CALLED: Hash(String, Hash::TypeRef)#[]=" / abort (134).
# This blocked the bootstrapped stage-2 compiler (s2b) right after lower_main.
#
# Fix: resolve each type arg via resolve_type_name_in_context in the Call branch,
# mirroring the Generic branch, so `TypeRef` -> `Adamas::MIR::TypeRef` once, at the
# site, and every downstream reference uses the same FQ identity.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hash_dual_typeref.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

fail=0
run_case() {
  local name="$1" src="$2" expect="$3"
  local cr="$TMP_DIR/$name.cr" bin="$TMP_DIR/$name.bin" out="$TMP_DIR/$name.out"
  printf '%s' "$src" >"$cr"
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

# Key-side: ::Hash(TypeRef, String).new where TypeRef is an ambiguous nested type.
# Was: STUB CALLED Hash(TypeRef, String)#... via phantom Hash::TypeRef (abort 134).
run_case key_side 'module Adamas::HIR
  struct TypeRef
    def initialize(@id : Int32); end
  end
end
module Adamas::MIR
  struct TypeRef
    def initialize(@id : Int32); end
  end
  class Backend
    def run
      h = ::Hash(TypeRef, String).new
      h[TypeRef.new(7)] = "x"
      STDERR.puts h.size
    end
  end
end
Adamas::MIR::Backend.new.run' "1"

# Value-side: mirrors mir.cr `extern_globals : ::Hash(String, TypeRef)` — the exact
# shape of the s2b stub `Hash(String, Hash::TypeRef)#[]=`.
run_case value_side 'module Adamas::HIR
  struct TypeRef
    def initialize(@id : Int32); end
  end
end
module Adamas::MIR
  struct TypeRef
    def initialize(@id : Int32); end
    def to_s(io : IO) : Nil
      io << @id
    end
  end
  class Backend
    def run
      h = ::Hash(String, TypeRef).new
      h["a"] = TypeRef.new(7)
      STDERR.puts h.size
    end
  end
end
Adamas::MIR::Backend.new.run' "1"

if [[ "$fail" -ne 0 ]]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
