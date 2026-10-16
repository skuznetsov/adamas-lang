#!/usr/bin/env bash
# Infer callee type parameters from initializer restrictions and actual arguments.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/constructor-restriction-inference.XXXXXX")"
cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 || "${KEEP_TMP:-0}" == "1" ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT
if [[ ! -x "$COMPILER" || ! -x "$ORIGINAL_CRYSTAL" ]]; then
  echo "ERROR: candidate and original compilers must be executable" >&2
  exit 2
fi
cat >"$WORK_DIR/main.cr" <<'CRYSTAL'
class ConstraintCarrier(T)
  def initialize(@value : T)
  end
  def value : T
    @value
  end
end
class ConstructorAction(T)
  def initialize(@carrier : ConstraintCarrier(T))
  end
  def value : T
    @carrier.value
  end
end
class NestedAction(T)
  def initialize(@carrier : ConstraintCarrier(ConstraintCarrier(T)))
  end
  def value : T
    @carrier.value.value
  end
end
class ReorderedAction(T, U)
  def initialize(@tag : U, @carrier : ConstraintCarrier(T))
  end
  def value : T
    @carrier.value
  end
end
class NamedAction(T, U)
  def initialize(@tag : U, @carrier : ConstraintCarrier(T))
  end
  def value : T
    @carrier.value
  end
end
class NamedOnlyAction(T)
  def initialize(*, @carrier : ConstraintCarrier(T))
  end
  def value : T
    @carrier.value
  end
end
class AbstractExtraAction(T)
  def initialize(tag : Int, @carrier : ConstraintCarrier(T))
  end
  def value : T
    @carrier.value
  end
end
class DefaultedAction(T)
  def initialize(@carrier : ConstraintCarrier(T), tag : Int = 7)
  end
  def value : T
    @carrier.value
  end
end
class SpecificAction(T)
  def initialize(carrier : ConstraintCarrier(T))
    @value = carrier.value
  end
  def initialize(@value : T)
  end
  def value : T
    @value
  end
end
class ReverseSpecificAction(T)
  def initialize(@value : T)
  end
  def initialize(carrier : ConstraintCarrier(T))
    @value = carrier.value
  end
  def value : T
    @value
  end
end
module ConstructorEnumOwner
  enum Mode
    Checked
    Unchecked
  end
  class EnumAction(T)
    def initialize(@carrier : ConstraintCarrier(T), @mode : Mode = :checked)
    end
    def value : T
      @carrier.value
    end
    def mode_value : Int32
      @mode.value
    end
  end
end
module ConstructorProjection(S)
  abstract def value : S
end
class ProjectionCarrier(T)
  include ConstructorProjection(T)
  def initialize(@value : T)
  end
  def value : T
    @value
  end
end
class ProjectionContext(S)
  def initialize(@action : ConstructorProjection(S))
  end
  def value : S
    @action.value
  end
end
a = ConstructorAction.new(ConstraintCarrier(Int32).new(65))
puts typeof(a).name
puts a.value
b = NestedAction.new(ConstraintCarrier(ConstraintCarrier(Int32)).new(ConstraintCarrier(Int32).new(66)))
puts typeof(b).name
puts b.value
c = ReorderedAction.new(7_i64, ConstraintCarrier(Int32).new(67))
puts typeof(c).name
puts c.value
d = NamedAction.new(carrier: ConstraintCarrier(Int32).new(68), tag: 7_i64)
puts typeof(d).name
puts d.value
e = NamedOnlyAction.new(carrier: ConstraintCarrier(Int32).new(69))
puts typeof(e).name
puts e.value
f = AbstractExtraAction.new(7_u64, ConstraintCarrier(Int32).new(70))
puts typeof(f).name
puts f.value
g = DefaultedAction.new(ConstraintCarrier(Int32).new(71))
puts typeof(g).name
puts g.value
h = SpecificAction.new(ConstraintCarrier(Int32).new(72))
puts typeof(h).name
puts h.value
i = ReverseSpecificAction.new(ConstraintCarrier(Int32).new(73))
puts typeof(i).name
puts i.value
j = ConstructorEnumOwner::EnumAction.new(ConstraintCarrier(Int32).new(74), :unchecked)
puts typeof(j).name
puts j.value
puts j.mode_value
k = ProjectionContext.new(ProjectionCarrier(Int32).new(75))
puts typeof(k).name
puts k.value
CRYSTAL
cat >"$WORK_DIR/conflict.cr" <<'CRYSTAL'
class ConstraintCarrier(T)
  def initialize(@value : T)
  end
end
class ConflictingAction(T)
  def initialize(@left : ConstraintCarrier(T), @right : ConstraintCarrier(T))
  end
end
ConflictingAction.new(ConstraintCarrier(Int32).new(1), ConstraintCarrier(Int64).new(2_i64))
CRYSTAL
cat >"$WORK_DIR/invalid_enum.cr" <<'CRYSTAL'
class ConstraintCarrier(T)
  def initialize(@value : T)
  end
end
module ConstructorEnumOwner
  enum Mode
    Checked
    Unchecked
  end
  class EnumAction(T)
    def initialize(@carrier : ConstraintCarrier(T), @mode : Mode)
    end
  end
end
ConstructorEnumOwner::EnumAction.new(ConstraintCarrier(Int32).new(1), :missing)
CRYSTAL
cat >"$WORK_DIR/expected" <<'EXPECTED'
ConstructorAction(Int32)
65
NestedAction(Int32)
66
ReorderedAction(Int32, Int64)
67
NamedAction(Int32, Int64)
68
NamedOnlyAction(Int32)
69
AbstractExtraAction(Int32)
70
DefaultedAction(Int32)
71
SpecificAction(Int32)
72
ReverseSpecificAction(Int32)
73
ConstructorEnumOwner::EnumAction(Int32)
74
1
ProjectionContext(Int32)
75
EXPECTED
for stage in original candidate; do
  compiler="$COMPILER"
  args=("$WORK_DIR/main.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/$stage")
  reject_args=("$WORK_DIR/conflict.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/$stage.conflict")
  if [[ "$stage" == "original" ]]; then
    compiler="$ORIGINAL_CRYSTAL"
    args=(build "$WORK_DIR/main.cr" -o "$WORK_DIR/$stage" --no-debug --error-trace --link-flags=-fuse-ld=/usr/bin/ld)
    reject_args=(build "$WORK_DIR/conflict.cr" -o "$WORK_DIR/$stage.conflict" --no-debug --error-trace --link-flags=-fuse-ld=/usr/bin/ld)
  fi
  if ! CRYSTAL_CACHE_DIR="$WORK_DIR/$stage.cache" \
      "$ROOT_DIR/scripts/run_safe.sh" "$compiler" 180 8192 "${args[@]}" \
      >"$WORK_DIR/$stage.build.log" 2>&1; then
    echo "FAIL[$stage]: compilation failed" >&2
    tail -20 "$WORK_DIR/$stage.build.log" >&2
    exit 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
      "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$stage" 10 512 \
      >"$WORK_DIR/$stage.actual" 2>"$WORK_DIR/$stage.run.log"; then
    echo "FAIL[$stage]: runtime failed" >&2
    tail -20 "$WORK_DIR/$stage.run.log" >&2
    exit 1
  fi
  if ! diff -u "$WORK_DIR/expected" "$WORK_DIR/$stage.actual" >&2; then
    echo "FAIL[$stage]: inferred types or payloads differ" >&2
    exit 1
  fi
  set +e
  CRYSTAL_CACHE_DIR="$WORK_DIR/$stage.cache" \
    "$ROOT_DIR/scripts/run_safe.sh" "$compiler" 180 8192 "${reject_args[@]}" \
    >"$WORK_DIR/$stage.reject.log" 2>&1
  status=$?
  set -e
  if [[ "$status" != 1 ]]; then
    echo "FAIL[$stage]: conflicting restrictions must fail compilation (exit=$status)" >&2
    exit 1
  fi
  pattern="expected argument #2.*ConstraintCarrier\(Int32\).*ConstraintCarrier\(Int64\)"
  if [[ "$stage" == "candidate" ]]; then
    pattern='cannot infer ConflictingAction type arguments from initializer restrictions'
  fi
  if ! grep -Eq "$pattern" "$WORK_DIR/$stage.reject.log"; then
    echo "FAIL[$stage]: conflict rejected for an unrelated reason" >&2
    tail -20 "$WORK_DIR/$stage.reject.log" >&2
    exit 1
  fi
  reject_args=("$WORK_DIR/invalid_enum.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/$stage.invalid_enum")
  if [[ "$stage" == "original" ]]; then
    reject_args=(build "$WORK_DIR/invalid_enum.cr" -o "$WORK_DIR/$stage.invalid_enum" --no-debug --error-trace --link-flags=-fuse-ld=/usr/bin/ld)
  fi
  set +e
  CRYSTAL_CACHE_DIR="$WORK_DIR/$stage.cache" \
    "$ROOT_DIR/scripts/run_safe.sh" "$compiler" 180 8192 "${reject_args[@]}" \
    >"$WORK_DIR/$stage.invalid_enum.log" 2>&1
  status=$?
  set -e
  if [[ "$status" != 1 ]]; then
    echo "FAIL[$stage]: invalid enum member must fail compilation (exit=$status)" >&2
    exit 1
  fi
  pattern='(undefined.*[Mm]ode|no.*[Mm]ode|[Mm]ode.*(member|constant)|invalid.*enum)'
  if [[ "$stage" == "candidate" ]]; then
    pattern='cannot infer ConstructorEnumOwner::EnumAction type arguments from initializer restrictions'
  fi
  if ! grep -Eq "$pattern" "$WORK_DIR/$stage.invalid_enum.log"; then
    echo "FAIL[$stage]: invalid enum member rejected for an unrelated reason" >&2
    tail -20 "$WORK_DIR/$stage.invalid_enum.log" >&2
    exit 1
  fi
  echo "PASS[$stage]: constructor restrictions infer nested, reordered, named and default arguments; overload order and enum payload agree; conflicts and invalid enum members reject"
done
