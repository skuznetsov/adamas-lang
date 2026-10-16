#!/usr/bin/env bash
# Preserve source pointee identity while taking the address of existing storage.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}"
RUN_SAFE="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pointerof-source-identity.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" -eq 0 && "${KEEP_TMP:-0}" != "1" ]]; then
    python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$WORK_DIR"
  else
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  fi
}
trap cleanup EXIT
[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL" ]]
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
export ADAMAS_LLVM_CACHE=0
cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
class PointerSourceBox(T)
  def initialize(@value : T)
  end

  def read : Int32
    accept(pointerof(@value))
  end

  def accept(value : Pointer(T)) : Int32
    value.value
  end
end

class PointerSourceParent
  @value : Int32 = 41
end

class PointerSourceChild < PointerSourceParent
  def read : Int32
    accept(pointerof(@value))
  end

  def accept(value : Pointer(Int32)) : Int32
    value.value
  end
end

def read_nested(value : Pointer(Pointer(Int32))) : Int32
  value.value.value
end

def read_callback(value : Pointer(Proc(Int32))) : Int32
  value.value.call
end

struct PointerSourceValueCell
  def initialize(@number : Int32); end

  def update : Int32
    address = pointerof(@number)
    address.value = 47
    @number
  end
end

class PointerSourceCallbackCell
  def initialize(@callback : Proc(Int32)); end

  def read : Int32
    read_callback(pointerof(@callback))
  end

  def read_callback(address : Pointer(Proc(Int32))) : Int32
    address.value.call
  end
end

class PointerSourceReferenceCell
  def initialize(@text : String); end

  def update : String
    address = pointerof(@text)
    address.value = "second"
    @text
  end
end

puts PointerSourceBox(Int32).new(42).read
puts PointerSourceChild.new.read
number = 43
ptr = pointerof(number)
puts read_nested(pointerof(ptr))
callback = ->{ 73 }
puts read_callback(pointerof(callback))
puts "A".to_unsafe.value.to_i
puts PointerSourceValueCell.new(11).update
puts PointerSourceCallbackCell.new(->{ 79 }).read
puts PointerSourceReferenceCell.new("first").update
CRYSTAL
printf '42\n41\n43\n73\n65\n47\n79\nsecond\n' >"$WORK_DIR/expected.stdout"
for stage in original candidate; do
  cache="$WORK_DIR/${stage}_cache"
  mkdir "$cache"
  if [[ "$stage" == "original" ]]; then
    if ! CRYSTAL_CACHE_DIR="$cache" "$RUN_SAFE" "$ORIGINAL_CRYSTAL" 180 8192 \
      build "$WORK_DIR/probe.cr" --no-debug --error-trace \
      --link-flags=-fuse-ld=/usr/bin/ld -o "$WORK_DIR/$stage" \
      >"$WORK_DIR/$stage.build.log" 2>&1; then
      cat "$WORK_DIR/$stage.build.log" >&2
      exit 1
    fi
  else
    if ! CRYSTAL_CACHE_DIR="$cache" "$RUN_SAFE" "$COMPILER" 180 8192 \
      "$WORK_DIR/probe.cr" --no-debug --no-ast-cache --no-llvm-cache \
      -o "$WORK_DIR/$stage" >"$WORK_DIR/$stage.build.log" 2>&1; then
      cat "$WORK_DIR/$stage.build.log" >&2
      exit 1
    fi
  fi
  python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$cache"
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 "$RUN_SAFE" "$WORK_DIR/$stage" 15 1024 \
    >"$WORK_DIR/$stage.stdout" 2>"$WORK_DIR/$stage.run.log"; then
    cat "$WORK_DIR/$stage.run.log" >&2
    exit 1
  fi
  diff -u "$WORK_DIR/expected.stdout" "$WORK_DIR/$stage.stdout"
done
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"
echo 'PASS: pointerof generic/inherited ivars, nested pointers, Proc storage, String bytes, and value/reference writeback match Crystal'
