#!/usr/bin/env bash
# Regression test (L14): a local referenced ONLY as a named-argument value
# inside a materialized block proc must be captured.
#
# Bug: collect_proc_body_ident_walk's CallNode case walked callee/args/block
# but NOT node.named_args, so identifiers appearing only as named-arg values
# were invisible to block-proc capture detection. No closure cell was
# allocated; lowering the call inside the proc then materialized a fresh
# UNINITIALIZED local slot and passed its ADDRESS as the argument value.
# In the self-hosted compiler this fed lower_method a stack pointer as
# `forced_full_name` (via the with_isolated_type_param_map block in
# lower_function_if_needed_impl), registering a Function whose name String
# pointed into a dead stack frame — the veto-s2 SIGSEGV in
# Hash(String, Function)#key_hash during invalidate_lowered_layout_functions.
# Same omission fixed in detect_written_captures_walk and
# proc_expr_has_implicit_receiver_call?.
set -euo pipefail

COMPILER="${1:-./bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named_arg_capture.XXXXXX")"
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

# String local used only as a named-arg value in a proc-materialized block.
# Was: TAG=<stack garbage> (address of an uninitialized slot passed as String).
run_case string_capture 'def callee(a : Int32, *, tag : String) : Nil
  STDERR.puts "TAG=#{tag}"
end

def with_wrap(&block : -> Nil)
  block.call
end

def driver
  t = "hello-tag"
  with_wrap do
    callee(1, tag: t)
  end
end

driver' "TAG=hello-tag"

# Same-name shorthand (arg name == local name) and a Bool — mirrors the
# lower_method callsite shape (force_class_method:/forced_method_name:).
run_case same_name_bool 'def callee(a : Int32, *, flag : Bool, label : String) : Nil
  STDERR.puts "#{label}=#{flag}"
end

def with_wrap(&block : -> Nil)
  block.call
end

def driver
  flag = true
  label = "L"
  with_wrap do
    callee(1, flag: flag, label: label)
  end
end

driver' "L=true"

if [[ "$fail" -ne 0 ]]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
