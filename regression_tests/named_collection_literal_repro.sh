#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adamas_named_collection_literal.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found or not executable: $COMPILER" >&2
  exit 2
fi

run_case() {
  local name="$1"
  local prelude_mode="$2"
  local source="$WORK_DIR/$name.cr"
  local binary="$WORK_DIR/$name"
  local compile_log="$WORK_DIR/$name.compile.log"
  local runtime_log="$WORK_DIR/$name.runtime.log"

  if [[ "$prelude_mode" == "no-prelude" ]]; then
    if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 90 4096 \
      "$source" --no-prelude -o "$binary" >"$compile_log" 2>&1; then
      cat "$compile_log" >&2
      echo "FAIL[$name]: compiler failed" >&2
      exit 1
    fi
  else
    if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 \
      "$source" -o "$binary" >"$compile_log" 2>&1; then
      cat "$compile_log" >&2
      echo "FAIL[$name]: compiler failed" >&2
      exit 1
    fi
  fi

  if ! "$ROOT_DIR/scripts/run_safe.sh" "$binary" 5 512 >"$runtime_log" 2>&1; then
    cat "$runtime_log" >&2
    echo "FAIL[$name]: generated program failed" >&2
    exit 1
  fi
}

cat >"$WORK_DIR/order.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class NamedCollectionProbeState
  @@value : Int32 = 0

  def self.mark(value : Int32) : Int32
    @@value = @@value * 10 + value
    value
  end

  def self.value : Int32
    @@value
  end
end

class NamedCollectionProbeBag(T)
  @count : Int32

  def initialize
    NamedCollectionProbeState.mark(1)
    @count = 0
  end

  def <<(value : T)
    @count += 1
    NamedCollectionProbeState.mark(2)
    self
  end

  def count : Int32
    @count
  end
end

def named_collection_complex_value : Int32
  NamedCollectionProbeState.mark(3)
end

empty = NamedCollectionProbeBag(Int32){}
LibC.exit(1) unless empty.count == 0
LibC.exit(2) unless NamedCollectionProbeState.value == 1

bag = NamedCollectionProbeBag(Int32){named_collection_complex_value, 4}
LibC.exit(3) unless bag.count == 2
LibC.exit(4) unless NamedCollectionProbeState.value == 13122

ordinary = [1, 2]
LibC.exit(5) unless ordinary.size == 2
LibC.exit(0)
CR

run_case order no-prelude

cat >"$WORK_DIR/set_hash.cr" <<'CR'
require "set"

lib LibC
  fun exit(status : Int32) : NoReturn
end

value = "module"
members = Set(String){value}
index = {} of String => Set(String)
index["module"] = members
stored = index["module"]

LibC.exit(1) unless stored.includes?(value)
LibC.exit(2) unless stored.size == 1
LibC.exit(0)
CR

run_case set_hash full-prelude

cat >"$WORK_DIR/splat.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class NamedCollectionSplatProbe(T)
  def initialize
  end

  def <<(value : T)
    self
  end
end

values = [1, 2]
probe = NamedCollectionSplatProbe(Int32){(*values,)}
LibC.exit(probe.object_id.to_i32)
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 90 4096 \
  "$WORK_DIR/splat.cr" --no-prelude -o "$WORK_DIR/splat" \
  >"$WORK_DIR/splat.compile.log" 2>&1
splat_status=$?
set -e
if [[ "$splat_status" -eq 0 ]]; then
  echo "FAIL[splat]: unsupported named collection splat unexpectedly compiled" >&2
  cat "$WORK_DIR/splat.compile.log" >&2
  exit 1
fi
if ! rg -Fq "with splat elements yet" "$WORK_DIR/splat.compile.log"; then
  echo "FAIL[splat]: compiler rejected input without the bounded diagnostic" >&2
  cat "$WORK_DIR/splat.compile.log" >&2
  exit 1
fi

echo "PASS: named collection literals preserve explicit T return, empty construction, evaluation order, Set/Hash storage, and fail-closed splat forms"
