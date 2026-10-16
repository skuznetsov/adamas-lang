#!/usr/bin/env bash
# Preserve applied generic module identity through both member-call syntaxes.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-module-dispatch.XXXXXX")"
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
cat >"$WORK_DIR/definitions.cr" <<'CONTENTS'
module ProjectionAction(S)
  abstract def value : S
end
module ProjectionRelay(U)
  include ProjectionAction(U)
end
class ProjectionContext(S)
  def initialize(@action : ProjectionAction(S))
  end
  def value : S
    @action.value
  end
end
class ProjectionCarrier(T)
  include ProjectionAction(T)
  def initialize(@value : T)
  end
  def value : T
    @value
  end
  def context
    ProjectionContext.new(self)
  end
end
class RelayCarrier(T)
  include ProjectionRelay(T)
  def initialize(@value : T)
  end
  def value : T
    @value
  end
end
class ConcreteCarrier
  include ProjectionAction(Int32)
  def value : Int32
    67
  end
end
module ProjectionNamespace
  module Action(S)
    abstract def value : S
  end
  class Carrier(T)
    include Action(T)
    def initialize(@value : T)
    end
    def value : T
      @value
    end
  end
  class Context(S)
    def initialize(@action : Action(S))
    end
    def value : S
      @action.value
    end
  end
end
class ParentCarrier(T)
  def initialize(@value : T)
  end
  def value : T
    @value
  end
end
class ChildCarrier(T) < ParentCarrier(T)
end
class ParentContext(S)
  def initialize(@carrier : ParentCarrier(S))
  end
  def value : S
    @carrier.value
  end
end
CONTENTS
cat >"$WORK_DIR/cases32.cr" <<'CONTENTS'
a = ProjectionCarrier(Int32).new(65).context
puts typeof(a).name
puts a.value
puts a.value()
b = ProjectionContext.new(RelayCarrier(Int32).new(66))
puts typeof(b).name
puts b.value
puts b.value()
c = ProjectionContext.new(ConcreteCarrier.new)
puts typeof(c).name
puts c.value
puts c.value()
d = ProjectionNamespace::Context.new(ProjectionNamespace::Carrier(Int32).new(68))
puts typeof(d).name
puts d.value
puts d.value()
e = ParentContext.new(ChildCarrier(Int32).new(69))
puts typeof(e).name
puts e.value
puts e.value()

CONTENTS
cat >"$WORK_DIR/cases64.cr" <<'CONTENTS'
f = ProjectionContext(Int64).new(ProjectionCarrier(Int64).new(4294967366_i64))
puts typeof(f).name
puts f.value
puts f.value()
g = ProjectionContext.new(RelayCarrier(Int64).new(4294967367_i64))
puts typeof(g).name
puts g.value
puts g.value()
h = ProjectionNamespace::Context.new(ProjectionNamespace::Carrier(Int64).new(4294967368_i64))
puts typeof(h).name
puts h.value
puts h.value()
CONTENTS
cat >"$WORK_DIR/expected32" <<'CONTENTS'
ProjectionContext(Int32)
65
65
ProjectionContext(Int32)
66
66
ProjectionContext(Int32)
67
67
ProjectionNamespace::Context(Int32)
68
68
ParentContext(Int32)
69
69
CONTENTS
cat >"$WORK_DIR/expected64" <<'CONTENTS'
ProjectionContext(Int64)
4294967366
4294967366
ProjectionContext(Int64)
4294967367
4294967367
ProjectionNamespace::Context(Int64)
4294967368
4294967368
CONTENTS
cat "$WORK_DIR/definitions.cr" "$WORK_DIR/cases32.cr" "$WORK_DIR/cases64.cr" >"$WORK_DIR/forward.cr"
cat "$WORK_DIR/definitions.cr" "$WORK_DIR/cases64.cr" "$WORK_DIR/cases32.cr" >"$WORK_DIR/reverse.cr"
cat "$WORK_DIR/expected32" "$WORK_DIR/expected64" >"$WORK_DIR/forward.expected"
cat "$WORK_DIR/expected64" "$WORK_DIR/expected32" >"$WORK_DIR/reverse.expected"
for stage in original candidate; do
  for order in forward reverse; do
    compiler="$COMPILER"
    args=("$WORK_DIR/$order.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/$stage.$order")
    if [[ "$stage" == "original" ]]; then
      compiler="$ORIGINAL_CRYSTAL"
      args=(build "$WORK_DIR/$order.cr" -o "$WORK_DIR/$stage.$order" --no-debug --error-trace --link-flags=-fuse-ld=/usr/bin/ld)
    fi
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/$stage.cache" \
        "$ROOT_DIR/scripts/run_safe.sh" "$compiler" 180 8192 "${args[@]}" \
        >"$WORK_DIR/$stage.$order.build.log" 2>&1; then
      echo "FAIL[$stage/$order]: compilation failed" >&2
      tail -20 "$WORK_DIR/$stage.$order.build.log" >&2
      exit 1
    fi
    if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
        "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$stage.$order" 10 512 \
        >"$WORK_DIR/$stage.$order.actual" 2>"$WORK_DIR/$stage.$order.run.log"; then
      echo "FAIL[$stage/$order]: runtime failed" >&2
      tail -20 "$WORK_DIR/$stage.$order.run.log" >&2
      exit 1
    fi
    if ! diff -u "$WORK_DIR/$order.expected" "$WORK_DIR/$stage.$order.actual" >&2; then
      echo "FAIL[$stage/$order]: concrete module values or types differ" >&2
      exit 1
    fi
    echo "PASS[$stage/$order]: direct, transitive and qualified module views preserve Int32/Int64 identity"
  done
done
