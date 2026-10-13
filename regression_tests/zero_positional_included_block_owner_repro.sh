#!/usr/bin/env bash
# Zero-positional block methods copied through generic module includes must
# keep the concrete including receiver, while unrelated receivers, direct
# overrides, and positional overloads retain their own dispatch.
#
# The separate Hash#any? fixture exercises the same zero-positional block
# lookup through Enumerable with tuple-destructured, tuple-single, empty,
# reserved-key, and unknown-value map controls.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SAFE_RUN="$ROOT_DIR/scripts/run_safe.sh"

if [[ -n "${ADAMAS_ZERO_POSITIONAL_OWNER_AUDIT_DIR:-}" ]]; then
  WORK_DIR="$ADAMAS_ZERO_POSITIONAL_OWNER_AUDIT_DIR"
  mkdir -p "$WORK_DIR"
  KEEP_WORK_DIR=1
else
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zero_positional_owner.XXXXXX")"
  KEEP_WORK_DIR=0
fi
if [[ "$KEEP_WORK_DIR" -eq 0 ]]; then
  trap 'rm -rf "$WORK_DIR"' EXIT
fi

cat >"$WORK_DIR/owner.cr" <<'CR'
lib LibC
  fun printf(format : UInt8*, ...) : Int32
  fun exit(status : Int32) : NoReturn
end

class UnrelatedPeer
  def zero_block(&block : Int32 -> Int32) : Int32
    700 + yield(0)
  end

  def marker : Int32
    90
  end
end

module ZeroPositionalSource(T)
  def zero_block(&block : T -> Int32) : Int32
    yield sample_value
  end

  def marker : Int32
    {% if @type.name == "ZeroDirect" %}
      11
    {% elsif @type.name == "ZeroTransitiveInt" %}
      12
    {% elsif @type.name == "ZeroTransitiveFloat" %}
      13
    {% elsif @type.name == "ZeroOverride" %}
      14
    {% else %}
      1
    {% end %}
  end

  def wrapped_zero : Int32
    zero_block { |value| marker + value.to_i32 }
  end

  def choose(value : T) : Int32
    100
  end

  def choose(&block : T -> Int32) : Int32
    200 + yield(sample_value)
  end

  def invoke_pattern(value : T) : Int32
    choose(value)
  end

  def invoke_block : Int32
    choose { |value| marker + value.to_i32 }
  end

  def invoke_peer(peer : UnrelatedPeer) : Int32
    peer.zero_block { |value| peer.marker + value }
  end
end

module ZeroPositionalRelay(T)
  include ZeroPositionalSource(T)
end

class ZeroDirect
  include ZeroPositionalSource(Int32)

  def sample_value : Int32
    1
  end
end

class ZeroTransitiveInt
  include ZeroPositionalRelay(Int32)

  def sample_value : Int32
    2
  end
end

class ZeroTransitiveFloat
  include ZeroPositionalRelay(Float64)

  def sample_value : Float64
    3.5
  end
end

class ZeroOverride
  include ZeroPositionalSource(Int32)

  def zero_block(&block : Int32 -> Int32) : Int32
    500 + yield(sample_value)
  end

  def sample_value : Int32
    4
  end
end

mask = 0
mask |= 1 unless ZeroDirect.new.wrapped_zero == 12
mask |= 2 unless ZeroTransitiveInt.new.wrapped_zero == 14
mask |= 4 unless ZeroTransitiveFloat.new.wrapped_zero == 16
mask |= 8 unless ZeroOverride.new.wrapped_zero == 518
mask |= 16 unless ZeroDirect.new.invoke_pattern(7) == 100
mask |= 32 unless ZeroTransitiveFloat.new.invoke_pattern(7.5) == 100
mask |= 64 unless ZeroDirect.new.invoke_block == 212
mask |= 128 unless ZeroTransitiveInt.new.invoke_block == 214
mask |= 256 unless ZeroTransitiveFloat.new.invoke_block == 216
mask |= 512 unless ZeroDirect.new.invoke_peer(UnrelatedPeer.new) == 790
LibC.printf("FAILURE_MASK=%d\n", mask)
LibC.exit(mask == 0 ? 0 : 1)
CR

cat >"$WORK_DIR/hash_any.cr" <<'CR'
require "prelude"

lib LibC
  fun exit(status : Int32) : NoReturn
  fun printf(format : UInt8*, ...) : Int32
end

class BindingProbe
  def concrete?(value : String) : Bool
    name = value.strip
    return false if name.empty? || name == "_" || name == "Void" || name == "Unknown" || name == "self"
    return false if name.includes?('/') || name.includes?("typeof(")
    true
  end

  def matched?(map : Hash(String, String)) : Bool
    map.any? do |key, value|
      key != "__block_return__" && concrete?(value)
    end
  end
end

LibC.printf("start\n")
mask = 0
probe = BindingProbe.new
good = {"T" => "Float64"}
bad = {"__block_return__" => "Float64"}
unknown = {"T" => "Unknown"}
mask |= 1 unless probe.matched?(good)
mask |= 2 if probe.matched?(bad)
mask |= 4 if probe.matched?(unknown)
mask |= 8 unless good.any? { |key, value| key == "T" && value == "Float64" }
mask |= 16 unless good.any? { |pair| pair[0] == "T" && pair[1] == "Float64" }
mask |= 32 if ({} of String => String).any? { |key, value| key == "T" }
LibC.printf("mask:%d\n", mask)
LibC.exit(mask == 0 ? 0 : 1)
CR

run_case() {
  local name="$1"
  local source="$2"
  local mode="$3"
  local out="$WORK_DIR/$name"
  local build_log="$WORK_DIR/$name.build.log"
  local run_log="$WORK_DIR/$name.run.log"
  local -a compiler_args=()
  if [[ "$mode" == "no-prelude" ]]; then
    compiler_args+=(--no-prelude)
  fi

  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$name.build.resources" \
      env -u CRYSTAL_PATH ADAMAS_LLVM_CACHE=0 \
      "$SAFE_RUN" "$COMPILER" 600 8192 "$source" "${compiler_args[@]}" -o "$out" \
      >"$build_log" 2>&1; then
    echo "FAIL: $name compile failed" >&2
    tail -40 "$build_log" >&2
    exit 1
  fi

  if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$name.run.resources" \
      "$SAFE_RUN" "$out" 10 512 >"$run_log" 2>&1; then
    echo "FAIL: $name runtime failed" >&2
    cat "$run_log" >&2
    exit 1
  fi
  if ! grep -q '^\[EXIT: 0\]' "$run_log"; then
    echo "FAIL: $name returned nonzero" >&2
    cat "$run_log" >&2
    exit 1
  fi
}

run_case owner "$WORK_DIR/owner.cr" no-prelude
if ! grep -q '^FAILURE_MASK=0$' "$WORK_DIR/owner.run.log"; then
  echo "FAIL: zero-positional module-owner controls failed" >&2
  cat "$WORK_DIR/owner.run.log" >&2
  exit 1
fi

run_case hash_any "$WORK_DIR/hash_any.cr" prelude
if ! grep -q '^start$' "$WORK_DIR/hash_any.run.log" || \
   ! grep -q '^mask:0$' "$WORK_DIR/hash_any.run.log"; then
  echo "FAIL: full-prelude Hash#any? zero-positional controls failed" >&2
  cat "$WORK_DIR/hash_any.run.log" >&2
  exit 1
fi

echo "PASS: zero-positional included block owners and Hash#any? controls"
