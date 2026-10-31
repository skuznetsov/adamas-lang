#!/usr/bin/env bash
# Selected class macro branches must register complete include semantics.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/selected-macro-class-include.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

cat > "$WORK/marker_modules.cr" <<'CRYSTAL'
module SelectedIncludeA
  def marker : Int32
    65
  end
end
module SelectedIncludeB
  def marker : Int32
    66
  end
end
module SelectedIncludeC
  def marker : Int32
    67
  end
end
module SelectedIncludeD
  def marker : Int32
    68
  end
end
module SelectedIncludePoison
  @poison : Int32
  def initialize(@poison : Int32)
  end
  def forbidden : Int32
    @poison
  end
end
CRYSTAL
cat > "$WORK/output.cr" <<'CRYSTAL'
@[Link("c")]
lib SelectedIncludeOutput
  fun putchar(value : Int32) : Int32
end
CRYSTAL

cat > "$WORK/direct.body.cr" <<'CRYSTAL'
class SelectedIncludeProbe
  include SelectedIncludeA
end
SelectedIncludeOutput.putchar(SelectedIncludeProbe.new.marker)
CRYSTAL
cat > "$WORK/active_then.body.cr" <<'CRYSTAL'
class SelectedIncludeProbe
  {% if true %}
    include SelectedIncludeA
  {% else %}
    include SelectedIncludePoison
  {% end %}
end
SelectedIncludeOutput.putchar(SelectedIncludeProbe.new.marker)
CRYSTAL
cat > "$WORK/active_else.body.cr" <<'CRYSTAL'
class SelectedIncludeProbe
  {% if false %}
    include SelectedIncludePoison
  {% else %}
    include SelectedIncludeB
  {% end %}
end
SelectedIncludeOutput.putchar(SelectedIncludeProbe.new.marker)
CRYSTAL
cat > "$WORK/nested_then.body.cr" <<'CRYSTAL'
class SelectedIncludeProbe
  {% if true %}
    {% if false %}
      include SelectedIncludePoison
    {% else %}
      include SelectedIncludeC
    {% end %}
  {% else %}
    include SelectedIncludePoison
  {% end %}
end
SelectedIncludeOutput.putchar(SelectedIncludeProbe.new.marker)
CRYSTAL
cat > "$WORK/nested_else.body.cr" <<'CRYSTAL'
class SelectedIncludeProbe
  {% if false %}
    include SelectedIncludePoison
  {% else %}
    {% if true %}
      include SelectedIncludeD
    {% else %}
      include SelectedIncludePoison
    {% end %}
  {% end %}
end
SelectedIncludeOutput.putchar(SelectedIncludeProbe.new.marker)
CRYSTAL
cat > "$WORK/initializer.body.cr" <<'CRYSTAL'
module SelectedIncludeInitializer
  @marker : Int32
  def initialize
    @marker = 69
  end
  def marker : Int32
    @marker
  end
end
class SelectedIncludeProbe
  {% if true %}
    include SelectedIncludeInitializer
  {% end %}
end
SelectedIncludeOutput.putchar(SelectedIncludeProbe.new.marker)
CRYSTAL
sed '/{% if true %}/d; /{% end %}/d' "$WORK/initializer.body.cr" > "$WORK/direct_initializer.body.cr"
cat > "$WORK/included_macro.body.cr" <<'CRYSTAL'
module SelectedIncludeHook
  macro included
    def marker : Int32
      70
    end
  end
end
class SelectedIncludeProbe
  {% if true %}
    include SelectedIncludeHook
  {% end %}
end
SelectedIncludeOutput.putchar(SelectedIncludeProbe.new.marker)
CRYSTAL
sed '/{% if true %}/d; /{% end %}/d' "$WORK/included_macro.body.cr" > "$WORK/direct_included_macro.body.cr"
cat > "$WORK/false_branch.body.cr" <<'CRYSTAL'
class SelectedIncludeProbe
  {% if false %}
    include SelectedIncludePoison
  {% end %}
  def marker : Int32
    71
  end
end
SelectedIncludeOutput.putchar(SelectedIncludeProbe.new.marker)
CRYSTAL
cat > "$WORK/flag_then.body.cr" <<'CRYSTAL'
abstract class SelectedIncludeRoot
  abstract def around(&) : Bool
end
module SelectedIncludeLock
  def around(&) : Bool
    yield
    true
  end
end
abstract class SelectedIncludePolling < SelectedIncludeRoot
  {% if !flag?(:without_mt) && !flag?(:preview_mt) || flag?(:execution_context) %}
    include SelectedIncludeLock
  {% end %}
end
class SelectedIncludeKqueue < SelectedIncludePolling
end
def selected_include_return(owner : SelectedIncludeKqueue) : Int32
  owner.around { return 72 }
  90
end
SelectedIncludeOutput.putchar(selected_include_return(SelectedIncludeKqueue.new))
CRYSTAL
cat > "$WORK/override_before.body.cr" <<'CRYSTAL'
class SelectedIncludeProbe
  def marker : Int32
    73
  end
  {% if true %}
    include SelectedIncludeA
  {% end %}
end
SelectedIncludeOutput.putchar(SelectedIncludeProbe.new.marker)
CRYSTAL
cat > "$WORK/override_after.body.cr" <<'CRYSTAL'
class SelectedIncludeProbe
  {% if true %}
    include SelectedIncludeA
  {% end %}
  def marker : Int32
    74
  end
end
SelectedIncludeOutput.putchar(SelectedIncludeProbe.new.marker)
CRYSTAL
cat > "$WORK/false_method_rejected.body.cr" <<'CRYSTAL'
class SelectedIncludeProbe
  {% if false %}
    include SelectedIncludePoison
  {% end %}
end
SelectedIncludeProbe.new.forbidden
CRYSTAL
cat > "$WORK/generic_included_macro.body.cr" <<'CRYSTAL'
module SelectedIncludeFrameLeaf(T)
  def leaf_value(value : T) : T
    value
  end
end
module SelectedIncludeFrameOuter(T)
  macro included
    include SelectedIncludeFrameLeaf(T)
  end
end
class SelectedIncludeFrameProbe
  include SelectedIncludeFrameOuter(Int32)
end
def selected_include_needs_int(value : Int32) : Int32
  value &+ 65
end
SelectedIncludeOutput.putchar(selected_include_needs_int(SelectedIncludeFrameProbe.new.leaf_value(0)))
CRYSTAL
cat > "$WORK/generic_separate_owners.body.cr" <<'CRYSTAL'
module SelectedIncludeFrameNested
  module Leaf(T)
    def leaf_value(value : T) : T
      value
    end
  end
end
module SelectedIncludeFrameOuter(T)
  macro included
    include SelectedIncludeFrameNested::Leaf(T)
  end
end
class SelectedIncludeIntOwner
  {% if true %}
    include SelectedIncludeFrameOuter(Int32)
  {% end %}
end
class SelectedIncludeBoolOwner
  {% if true %}
    include SelectedIncludeFrameOuter(Bool)
  {% end %}
end
def selected_include_needs_int(value : Int32) : Int32
  SelectedIncludeOutput.putchar(65)
end
def selected_include_needs_bool(value : Bool) : Int32
  SelectedIncludeOutput.putchar(66)
end
selected_include_needs_int(SelectedIncludeIntOwner.new.leaf_value(0))
selected_include_needs_bool(SelectedIncludeBoolOwner.new.leaf_value(true))
CRYSTAL
# This stronger adversary also exercises the existing same-owner visited-base
# collision. Keep it strict and separate from the two-owner context witness.
cat > "$WORK/generic_two_specializations.body.cr" <<'CRYSTAL'
module SelectedIncludeFrameNested
  module Leaf(T)
    def leaf_value(value : T) : T
      value
    end
  end
end
module SelectedIncludeFrameOuter(T)
  macro included
    include SelectedIncludeFrameNested::Leaf(T)
  end
end
class SelectedIncludeFrameProbe
  include SelectedIncludeFrameOuter(Int32)
  include SelectedIncludeFrameOuter(Bool)
end
def selected_include_needs_int(value : Int32) : Int32
  SelectedIncludeOutput.putchar(65)
end
def selected_include_needs_bool(value : Bool) : Int32
  SelectedIncludeOutput.putchar(66)
end
selected_include_needs_int(SelectedIncludeFrameProbe.new.leaf_value(0))
selected_include_needs_bool(SelectedIncludeFrameProbe.new.leaf_value(true))
CRYSTAL
cat > "$WORK/include_site_namespace.body.cr" <<'CRYSTAL'
module IncludeNamespaceOwner
  module Leaf(T)
    def leaf_value(value : T) : T
      value
    end
    def source_marker : Int32
      65
    end
  end

  module Outer(T)
    macro included
      include Leaf(T)
    end
  end
end

module IncludeNamespaceConsumer
  module Leaf(T)
    def leaf_value(value : T) : T
      value
    end
    def source_marker : Int32
      66
    end
  end

  class Probe
    include IncludeNamespaceOwner::Outer(Int32)
  end
end

def include_namespace_needs_int(value : Int32) : Int32
  SelectedIncludeOutput.putchar(65)
end

SelectedIncludeOutput.putchar(IncludeNamespaceConsumer::Probe.new.source_marker)
include_namespace_needs_int(IncludeNamespaceConsumer::Probe.new.leaf_value(0))
CRYSTAL

cases=(direct active_then active_else nested_then nested_else initializer direct_initializer
  included_macro direct_included_macro false_branch flag_then override_before override_after false_method_rejected
  generic_included_macro generic_separate_owners generic_two_specializations include_site_namespace)
outputs=(A A B C D E E F F G H I J '' A AB AB BA)
for probe in "${cases[@]}"; do
  cat "$WORK/output.cr" "$WORK/marker_modules.cr" "$WORK/$probe.body.cr" > "$WORK/$probe.cr"
done
modes=(stock lazy eager)
[[ "${ORIGINAL_ONLY:-0}" == 1 ]] && modes=(stock)
for mode in "${modes[@]}"; do
  if [[ "$mode" == stock ]]; then
    compile=(env CRYSTAL_CACHE_DIR="$WORK/cache.stock" "$SAFE" "$ORIGINAL" 120 4096 build
      --prelude=empty --no-debug --link-flags="$LINK_FLAGS")
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    compile=("${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$CANDIDATE" 120 4096
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  for index in "${!cases[@]}"; do
    probe="${cases[$index]}"
    if [[ -n "${ONLY_CASES:-}" && ",${ONLY_CASES}," != *",${probe},"* ]]; then
      continue
    fi
    if [[ "$probe" == false_method_rejected ]]; then
      set +e
      "${compile[@]}" "$WORK/$probe.cr" -o "$WORK/$mode.$probe" > "$WORK/$mode.$probe.compile.log" 2>&1
      status=$?
      set -e
      [[ "$status" == 1 ]] || {
        cat "$WORK/$mode.$probe.compile.log" >&2
        printf 'FAIL: %s %s expected compile exit1, got%s\n' "$mode" "$probe" "$status" >&2
        exit 1
      }
      if ! grep -Eq 'undefined method.*forbidden|undefined function.*forbidden|no overload matches.*forbidden' "$WORK/$mode.$probe.compile.log"; then
        cat "$WORK/$mode.$probe.compile.log" >&2
        exit 1
      fi
    else
      "${compile[@]}" "$WORK/$probe.cr" -o "$WORK/$mode.$probe" > "$WORK/$mode.$probe.compile.log" 2>&1 || {
        cat "$WORK/$mode.$probe.compile.log" >&2
        exit 1
      }
      RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/$mode.$probe" 5 512 \
        > "$WORK/$mode.$probe.stdout" 2> "$WORK/$mode.$probe.run.log" || {
        cat "$WORK/$mode.$probe.run.log" >&2
        exit 1
      }
      printf '%s' "${outputs[$index]}" > "$WORK/$probe.expected.stdout"
      diff -u "$WORK/$probe.expected.stdout" "$WORK/$mode.$probe.stdout"
    fi
    printf 'PASS: %s %s\n' "$mode" "$probe"
  done
done
