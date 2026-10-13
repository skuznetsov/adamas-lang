#!/usr/bin/env bash
# String membership through Object#in? must use String content equality in
# both the variadic and concrete-Tuple inline paths.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/string_membership_value_equality.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

NO_PRELUDE_SRC="$WORK_DIR/no_prelude.cr"
NO_PRELUDE_BIN="$WORK_DIR/no_prelude"
cat >"$NO_PRELUDE_SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

LibC.exit(41) unless 7.in?(2, 7, 9)
LibC.exit(42) if 7.in?(2, 8, 9)
LibC.exit(43) unless 7.in?({2, 7, 9})
LibC.exit(44) if 7.in?({2, 8, 9})
LibC.exit(0)
CR

if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/no-prelude-build.resources" \
  "$RUN_SAFE" "$COMPILER" 60 4096 "$NO_PRELUDE_SRC" --no-prelude -o "$NO_PRELUDE_BIN" \
  >"$WORK_DIR/no-prelude-build.log" 2>&1; then
  cat "$WORK_DIR/no-prelude-build.log" >&2
  exit 1
fi
if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/no-prelude-run.resources" \
  "$RUN_SAFE" "$NO_PRELUDE_BIN" 5 512 >"$WORK_DIR/no-prelude-run.log" 2>&1; then
  cat "$WORK_DIR/no-prelude-run.log" >&2
  exit 1
fi

FULL_SRC="$WORK_DIR/full_prelude.cr"
FULL_BIN="$WORK_DIR/full_prelude"
cat >"$FULL_SRC" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

def dynamic_marker : String
  String.build do |io|
    io << '&'
  end
end

text = dynamic_marker
text_copy = text
tuple_match = dynamic_marker
equal_text = dynamic_marker
unequal_text = "x"
text_address = text.object_id

# The equal String values have separate backing objects from these literals.
LibC.exit(11) unless text == "&"
LibC.exit(12) unless text_copy.in?("+", "-", "|", "&", "^", "~")
LibC.exit(13) if text_copy.in?("+", "-", "|", "^", "~")

# The tuple shortcut must use the same content semantics as the variadic path.
LibC.exit(14) unless text_copy.in?({"other", tuple_match})
LibC.exit(15) if text_copy.in?({"x", "y"})
LibC.exit(16) if text_copy.in?({"x", 7})

# A primitive candidate is always unequal to a String, even when its raw bits
# equal the String object's address. Keep searching later String candidates.
LibC.exit(21) unless text_address == text.object_id
LibC.exit(22) if text.in?(unequal_text, text_address)
LibC.exit(23) if text.in?({unequal_text, text_address})
LibC.exit(24) unless text.in?(text_address, equal_text)
LibC.exit(25) unless text.in?({text_address, equal_text})

# Other statically known primitive types also compare unequal to String.
LibC.exit(26) if text.in?(true, nil)
LibC.exit(27) if text.in?('x', nil)
LibC.exit(28) if text.in?({true, nil})
LibC.exit(29) if text.in?({'x', nil})

# Keep primitive membership behavior unchanged in both shortcut shapes.
LibC.exit(17) unless 7.in?(2, 7, 9)
LibC.exit(18) if 7.in?(2, 8, 9)
LibC.exit(19) unless 7.in?({2, 7, 9})
LibC.exit(20) if 7.in?({2, 8, 9})
LibC.exit(0)
CR

if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/full-build.resources" \
  "$RUN_SAFE" "$COMPILER" 120 8192 "$FULL_SRC" -o "$FULL_BIN" \
  >"$WORK_DIR/full-build.log" 2>&1; then
  cat "$WORK_DIR/full-build.log" >&2
  exit 1
fi
if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/full-run.resources" \
  "$RUN_SAFE" "$FULL_BIN" 5 512 >"$WORK_DIR/full-run.log" 2>&1; then
  cat "$WORK_DIR/full-run.log" >&2
  exit 1
fi

echo "PASS: variadic and Tuple String membership use value equality; numeric controls pass"
