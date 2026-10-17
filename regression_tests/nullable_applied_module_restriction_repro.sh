#!/usr/bin/env bash
# Applied module arguments survive nilable restrictions before lazy includes register.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:?usage: nullable_applied_module_restriction_repro.sh COMPILER}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$COMPILER" && -x "$ORIGINAL" ]] || exit 2
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nullable_applied_module.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$WORK_DIR/original.cache" "$WORK_DIR/candidate.cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT
DEFAULT_LINK_FLAGS=""
[[ "$(uname -s)" != Darwin ]] || DEFAULT_LINK_FLAGS=-fuse-ld=/usr/bin/ld
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS-$DEFAULT_LINK_FLAGS}"
cat >"$WORK_DIR/common.cr" <<'CR'
module ProjectionBoundary
  module Item(T)
  end
  module ReopenedItem(T)
  end
  module Relay(U)
    include Item(U)
  end
  module Relay
    include ReopenedItem(U)
  end
  class Carrier(V)
    include Relay(V)
  end
end
module ProjectionNeighbor
  module Item(T)
  end
  class Carrier(V)
    include Item(V)
  end
end

def accepts_builtin(values : Enumerable(String)?) : Int32
  values ? 1 : 0
end

def accepts_declared(values : ProjectionBoundary::Item(String)?) : Int32
  values ? 2 : 0
end

def accepts_reopened(values : ProjectionBoundary::ReopenedItem(String)?) : Int32
  values ? 3 : 0
end

def accepts_exact(values : ProjectionBoundary::Item(String)) : Int32
  4
end
CR
cp "$WORK_DIR/common.cr" "$WORK_DIR/positive.cr"
cat >>"$WORK_DIR/positive.cr" <<'CR'
puts accepts_builtin(["one"])
puts accepts_builtin(Slice(String).new(1, "two"))
puts accepts_builtin(nil)
puts accepts_declared(ProjectionBoundary::Carrier(String).new)
puts accepts_declared(nil)
puts accepts_reopened(ProjectionBoundary::Carrier(String).new)
puts accepts_reopened(nil)
puts accepts_exact(ProjectionBoundary::Carrier(String).new)
CR
printf '1\n1\n0\n2\n0\n3\n0\n4\n' >"$WORK_DIR/expected"
for name in element applied erased namespace union; do
  cp "$WORK_DIR/common.cr" "$WORK_DIR/reject_$name.cr"
done
cat >>"$WORK_DIR/reject_element.cr" <<'CR'
accepts_builtin([1])
CR
cat >>"$WORK_DIR/reject_applied.cr" <<'CR'
accepts_declared(ProjectionBoundary::Carrier(Int32).new)
CR
cat >>"$WORK_DIR/reject_erased.cr" <<'CR'
accepts_exact(ProjectionBoundary::Carrier(Int32).new)
CR
cat >>"$WORK_DIR/reject_namespace.cr" <<'CR'
accepts_declared(ProjectionNeighbor::Carrier(String).new)
CR
cat >>"$WORK_DIR/reject_union.cr" <<'CR'
values = ARGV.empty? ? ["one"] : [1]
accepts_builtin(values)
CR
for stage in original candidate; do
  for name in positive reject_element reject_applied reject_erased reject_namespace reject_union; do
    bin="$WORK_DIR/$stage.$name"
    if [[ "$stage" == original ]]; then
      cmd=("$ORIGINAL" build "$WORK_DIR/$name.cr" -o "$bin" --no-debug)
      [[ -z "$DEFAULT_LINK_FLAGS" ]] || cmd+=("--link-flags=$DEFAULT_LINK_FLAGS")
    else
      cmd=("$COMPILER" "$WORK_DIR/$name.cr" -o "$bin" --no-debug --no-ast-cache --no-llvm-cache)
    fi
    rc=0
    env "CRYSTAL_CACHE_DIR=$WORK_DIR/$stage.cache" \
      "$ROOT_DIR/scripts/run_safe.sh" "${cmd[0]}" 180 8192 "${cmd[@]:1}" \
      >"$WORK_DIR/$stage.$name.compile.log" 2>&1 || rc=$?
    rm -rf "$WORK_DIR/$stage.cache"
    if [[ "$name" == positive ]]; then
      [[ "$rc" == 0 ]] || { tail -40 "$WORK_DIR/$stage.$name.compile.log" >&2; exit 1; }
      RUN_SAFE_PASSTHROUGH_STDIO=1 "$ROOT_DIR/scripts/run_safe.sh" "$bin" 10 512 \
        >"$WORK_DIR/$stage.actual" 2>"$WORK_DIR/$stage.run.log" || {
          tail -40 "$WORK_DIR/$stage.run.log" >&2; exit 1;
        }
      cmp "$WORK_DIR/expected" "$WORK_DIR/$stage.actual"
      if [[ "$stage" == candidate ]]; then
        cmp "$WORK_DIR/original.actual" "$WORK_DIR/candidate.actual"
      fi
    else
      [[ "$rc" == 1 ]] || {
        echo "FAIL[$stage/$name]: expected a restriction rejection, exit=$rc" >&2
        tail -40 "$WORK_DIR/$stage.$name.compile.log" >&2
        exit 1
      }
      rg -q 'no overload matches|expected argument restriction|expected argument #[0-9]+' \
        "$WORK_DIR/$stage.$name.compile.log" || {
          tail -40 "$WORK_DIR/$stage.$name.compile.log" >&2; exit 1;
        }
    fi
  done
done
echo 'PASS: nullable applied modules preserve include/reopening arguments and reject wrong elements, namespaces and union arms.'
