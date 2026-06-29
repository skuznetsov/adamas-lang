#!/usr/bin/env bash
# Regression: a generated s2 compiler used to lose the leaf component of a
# nested class name while registering a nested static method body.
#
# Repro shape:
#   class Exception
#     class CallStack
#       def self.skip(path : String) : Nil
#       end
#     end
#   end
#   Exception::CallStack.skip("x")
#
# Before the fix, the call lowered to Exception::CallStack.skip$String, but the
# nested class registration path registered the method body as
# Exception::.skip$String. The call symbol had no HIR/MIR body and the generated
# binary aborted in the backend dead-code stub:
#   STUB CALLED: Exception$CCCallStack$Dskip$$String
#
# The root was mixed String indexing in resolve_class_name_for_definition:
# rindex("::") produced a byte offset while name[(idx + 2)..] was not safe under
# the self-hosted compiler. Byte-slicing owner and leaf preserves
# Exception::CallStack in generated s2.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested_class_static_method_registration.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro.bin"
COMPILE_ERR="$TMP_DIR/compile.err"
RUN_OUT="$TMP_DIR/run.out"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$SRC" <<'CR'
class Exception
  class CallStack
    def self.skip(path : String) : Nil
    end
  end
end

Exception::CallStack.skip("x")
puts "RESULT=ok"
CR

set +e
"$COMPILER" "$SRC" --no-prelude -o "$BIN" >/dev/null 2>"$COMPILE_ERR"
compile_status=$?
set -e
if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: compile failed (status $compile_status)"
  cat "$COMPILE_ERR"
  exit 2
fi

set +e
./scripts/run_safe.sh "$BIN" 10 512 >"$RUN_OUT" 2>&1
run_status=$?
set -e

result_line="$(grep -E '^RESULT=' "$RUN_OUT" | head -1 || true)"
if [[ $run_status -eq 0 && "$result_line" == "RESULT=ok" ]]; then
  echo "PASS: nested static method body matches call symbol"
  exit 0
fi

echo "FAIL: nested static method body was missing or misregistered"
echo "expected: RESULT=ok"
echo "actual:   ${result_line:-<no RESULT line>}"
cat "$RUN_OUT"
exit 1
