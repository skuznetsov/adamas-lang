#!/usr/bin/env bash
# Method-forall identities must survive overload selection and body lowering.
# Cover long names, nested/pointer restrictions, included-module context, and
# rejection of inconsistent bindings or ordinary constants.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${COMPILER:-$ROOT_DIR/bin/adamas}}"
CASE="${2:-all}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal || true)}"
[[ -x "$RUN_SAFE" && -x "$COMPILER" && -x "$ORIGINAL" ]] || {
  echo "usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal $0 /path/to/adamas [all|forms|included|shadow|routing|rejections]" >&2
  exit 2
}
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/method-forall-binding.XXXXXX")"
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

cat >"$WORK_DIR/forms.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end

class Carrier(T)
end

def take(first : Element*, options : Carrier(Element)) : Element forall Element
  first.value
end

byte = 65_u8
Probe.putchar(take(pointerof(byte), Carrier(UInt8).new).to_i32)
wide = 66_i32
Probe.putchar(take(pointerof(wide), Carrier(Int32).new).to_i32)

def nested(value : Carrier(Carrier(AnotherName))) forall AnotherName
  {% if AnotherName == UInt8 %}
    Probe.putchar(67)
  {% else %}
    Probe.putchar(88)
  {% end %}
end
nested(Carrier(Carrier(UInt8)).new)

module Scoped
  def self.take(first : CharacterType*, options : Carrier(CharacterType)) : CharacterType forall CharacterType
    first.value
  end
end
scoped = 68_u8
Probe.putchar(Scoped.take(pointerof(scoped), Carrier(UInt8).new).to_i32)
CRYSTAL

cat >"$WORK_DIR/included.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end
class Carrier(T)
end
class Result(T)
end
module Converter(T, Word)
  def parse(first : UC*, last : UC*, value : T*, options : Carrier(UC)) : Result(UC) forall UC
    {% raise "UC must bind to the actual byte type" unless UC == UInt8 %}
    Probe.putchar(65)
    Result(UC).new
  end
end
struct Convert64
  include Converter(Float64, UInt64)
end
byte = 1_u8
value = 1.0_f64
Convert64.new.parse(pointerof(byte), pointerof(byte), pointerof(value), Carrier(UInt8).new)
CRYSTAL

cat >"$WORK_DIR/shadow.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end
class Carrier(T)
end
module Reader(UC)
  def take(first : UC*, options : Carrier(UC)) : UC forall UC
    first.value
  end
end
class Consumer
  include Reader(Int32)
end
byte = 69_u8
Probe.putchar(Consumer.new.take(pointerof(byte), Carrier(UInt8).new).to_i32)
CRYSTAL

# Existing source call-shape binding owns named/rest arguments. The new
# positional specialization demand must not bypass it with an unresolved stub.
cat >"$WORK_DIR/named_shadow.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end
class Carrier(T)
end
module Reader(UC)
  def take(first : UC*, *, options : Carrier(UC)) : Int32 forall UC
    {% if UC == UInt8 %}
      Probe.putchar(65)
    {% elsif UC == Int32 %}
      Probe.putchar(69)
    {% else %}
      Probe.putchar(88)
    {% end %}
  end
end
class Consumer
  include Reader(Int32)
end
byte = 1_u8
Consumer.new.take(pointerof(byte), options: Carrier(UInt8).new)
CRYSTAL

# Existing source call-shape binding owns named/rest arguments. The new
# positional specialization demand must not bypass it with an unresolved stub.
cat >"$WORK_DIR/splat_shadow.cr" <<'CRYSTAL'
lib Probe
  fun putchar(Int32) : Int32
end
class Carrier(T)
end
module Reader(UC)
  def take(first : UC*, options : Carrier(UC), *rest : UC) : Int32 forall UC
    {% if UC == UInt8 %}
      Probe.putchar(65)
    {% elsif UC == Int32 %}
      Probe.putchar(69)
    {% else %}
      Probe.putchar(88)
    {% end %}
  end
end
class Consumer
  include Reader(Int32)
end
byte = 1_u8
Consumer.new.take(pointerof(byte), Carrier(UInt8).new, 1_u8)
CRYSTAL

cat >"$WORK_DIR/conflict.cr" <<'CRYSTAL'
class Carrier(T)
end
def take(first : Element*, options : Carrier(Element)) forall Element
end
byte = 1_u8
take(pointerof(byte), Carrier(Int32).new)
CRYSTAL

cat >"$WORK_DIR/constant.cr" <<'CRYSTAL'
class Element
end
class Carrier(T)
end
def take(options : Carrier(Element))
end
take(Carrier(UInt8).new)
CRYSTAL

build_and_run() {
  local name="$1" expected="$2" stage="$3" compiler="$4"
  local binary="$WORK_DIR/$name.$stage.bin"
  local -a command
  if [[ "$stage" == original ]]; then
    command=("$compiler" build "$WORK_DIR/$name.cr" -o "$binary" --no-debug
             --link-flags="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
  else
    command=("$compiler" "$WORK_DIR/$name.cr" --no-ast-cache --no-llvm-cache --no-debug -o "$binary")
    command+=(--no-prelude)
  fi
  if ! env "CRYSTAL_CACHE_DIR=$WORK_DIR/$stage.cache" \
      "ADAMAS_EXTRA_LINK_FLAGS=${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      "$RUN_SAFE" "${command[0]}" 180 8192 "${command[@]:1}" \
      >"$WORK_DIR/$name.$stage.build.log" 2>&1; then
    tail -35 "$WORK_DIR/$name.$stage.build.log" >&2
    return 1
  fi
  rm -rf "$WORK_DIR/$stage.cache"
  if ! env RUN_SAFE_PASSTHROUGH_STDIO=1 \
      "$RUN_SAFE" "$binary" 15 1024 >"$WORK_DIR/$name.$stage.stdout" \
      2>"$WORK_DIR/$name.$stage.run.log"; then
    tail -35 "$WORK_DIR/$name.$stage.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$name.$stage.run.log"
  printf '%s' "$expected" >"$WORK_DIR/$name.expected"
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$name.$stage.stdout"
}

run_case() {
  local name="$1" expected="$2"
  build_and_run "$name" "$expected" original "$ORIGINAL"
  build_and_run "$name" "$expected" candidate "$COMPILER"
  diff -u "$WORK_DIR/$name.original.stdout" "$WORK_DIR/$name.candidate.stdout"
  printf 'PASS: %s method-forall binding\n' "$name"
}

reject_case() {
  local name="$1" stage compiler status binary
  for stage in original candidate; do
    compiler="$COMPILER"
    [[ "$stage" != original ]] || compiler="$ORIGINAL"
    binary="$WORK_DIR/$name.$stage.bin"
    local -a command
    if [[ "$stage" == original ]]; then
      command=("$compiler" build "$WORK_DIR/$name.cr" -o "$binary" --no-debug
               --link-flags="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}")
    else
      command=("$compiler" "$WORK_DIR/$name.cr" --no-prelude --no-ast-cache --no-llvm-cache --no-debug -o "$binary")
    fi
    status=0
    env "CRYSTAL_CACHE_DIR=$WORK_DIR/$stage.cache" \
        "$RUN_SAFE" "${command[0]}" 60 4096 "${command[@]:1}" \
        >"$WORK_DIR/$name.$stage.build.log" 2>&1 || status=$?
    rm -rf "$WORK_DIR/$stage.cache"
    if [[ "$status" != 1 ]] || ! grep -Eq 'no overload matches|Error: expected argument #[0-9]+' "$WORK_DIR/$name.$stage.build.log"; then
      echo "FAIL: $stage must reject $name at its source restriction (status=$status)" >&2
      tail -35 "$WORK_DIR/$name.$stage.build.log" >&2
      return 1
    fi
  done
  printf 'PASS: %s source restriction rejection\n' "$name"
}

case "$CASE" in
  all) run_case forms ABCD; run_case included A; run_case shadow E; run_case named_shadow A; run_case splat_shadow A; reject_case conflict; reject_case constant ;;
  forms) run_case forms ABCD ;;
  included) run_case included A ;;
  shadow) run_case shadow E ;;
  routing) run_case named_shadow A; run_case splat_shadow A ;;
  rejections) reject_case conflict; reject_case constant ;;
  *) echo "unknown case: $CASE" >&2; exit 2 ;;
esac
