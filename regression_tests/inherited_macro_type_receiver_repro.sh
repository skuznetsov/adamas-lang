#!/usr/bin/env bash
# Inherited instance methods with method-body macros must expand @type against
# the concrete receiver while retaining lexical constant lookup at the parent.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"

if [[ -n "${ADAMAS_MACRO_TYPE_AUDIT_DIR:-}" ]]; then
  WORK_DIR="$ADAMAS_MACRO_TYPE_AUDIT_DIR"
  mkdir -p "$WORK_DIR"
  KEEP_WORK_DIR=1
else
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inherited_macro_type_receiver.XXXXXX")"
  KEEP_WORK_DIR=0
fi
if [[ "$KEEP_WORK_DIR" -eq 0 ]]; then
  trap 'rm -rf "$WORK_DIR"' EXIT
fi

cat >"$WORK_DIR/repro.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class MacroBase
  PARENT_TOKEN = 7

  def receiver_marker : Int32
    {% if @type.name == "Bbb" %}
      42
    {% elsif @type.name == "Ccc" %}
      43
    {% elsif @type.name == "OwnOverride" %}
      44
    {% else %}
      1
    {% end %}
  end

  def receiver_marker_for(value : Int32) : Int32
    receiver_value = {% if @type.name == "Bbb" %}
      20
    {% elsif @type.name == "Ccc" %}
      30
    {% else %}
      10
    {% end %}
    receiver_value + value
  end

  # This deliberately combines receiver-sensitive macro expansion with an
  # unqualified parent constant. Changing @current_class must not change the
  # source method's lexical constant namespace.
  def lexical_and_receiver_marker : Int32
    receiver_value = {% if @type.name == "Bbb" %}
      42
    {% elsif @type.name == "Ccc" %}
      43
    {% elsif @type.name == "OwnOverride" %}
      44
    {% else %}
      1
    {% end %}
    PARENT_TOKEN + receiver_value
  end

  # A normal inherited method must remain parent-lexical without requiring a
  # per-receiver macro specialization.
  def inherited_lexical_value(value : Int32) : Int32
    PARENT_TOKEN + value
  end
end

class Bbb < MacroBase
  PARENT_TOKEN = 90
end

class Ccc < MacroBase
  PARENT_TOKEN = 91
end

class OwnOverride < MacroBase
  PARENT_TOKEN = 92

  def receiver_marker : Int32
    {% if @type.name == "OwnOverride" %}
      77
    {% else %}
      0
    {% end %}
  end
end

failures = 0
failures += 1 unless MacroBase.new.receiver_marker == 1
failures += 1 unless Bbb.new.receiver_marker == 42
failures += 1 unless Ccc.new.receiver_marker == 43
failures += 1 unless MacroBase.new.receiver_marker_for(3) == 13
failures += 1 unless Bbb.new.receiver_marker_for(3) == 23
failures += 1 unless Ccc.new.receiver_marker_for(3) == 33
failures += 1 unless OwnOverride.new.receiver_marker == 77
failures += 1 unless MacroBase.new.lexical_and_receiver_marker == 8
failures += 1 unless Bbb.new.lexical_and_receiver_marker == 49
failures += 1 unless Ccc.new.lexical_and_receiver_marker == 50
failures += 1 unless OwnOverride.new.lexical_and_receiver_marker == 51
failures += 1 unless MacroBase.new.inherited_lexical_value(5) == 12
failures += 1 unless Bbb.new.inherited_lexical_value(5) == 12
failures += 1 unless Ccc.new.inherited_lexical_value(5) == 12
failures += 1 unless OwnOverride.new.inherited_lexical_value(5) == 12
LibC.exit(failures == 0 ? 0 : 1)
CR

if ! "$SAFE_RUN" "$COMPILER" 300 8192 \
    "$WORK_DIR/repro.cr" --no-prelude -o "$WORK_DIR/repro" \
    >"$WORK_DIR/build.log" 2>&1; then
  echo "inherited macro receiver: compile failed" >&2
  tail -30 "$WORK_DIR/build.log" >&2
  exit 1
fi

"$SAFE_RUN" "$WORK_DIR/repro" 5 512 >"$WORK_DIR/run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/run.log"; then
  echo "inherited macro receiver: one or more comparisons failed (want EXIT 0):" >&2
  grep -E '^\[EXIT|^\[TIMEOUT|^\[KILLED' "$WORK_DIR/run.log" >&2 ||
    cat "$WORK_DIR/run.log" >&2
  exit 1
fi

echo inherited_macro_type_receiver_repro_ok
