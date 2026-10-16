#!/usr/bin/env bash
# Keep concrete receivers when inherited Object wrappers redispatch through self.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-/opt/homebrew/bin/crystal}}"
if [[ -n "${CRYSTAL_PATH:-}" ]]; then
  CRYSTAL_STDLIB="$CRYSTAL_PATH"
elif [[ -d "$ROOT_DIR/../crystal/src" ]]; then
  CRYSTAL_STDLIB="$(cd "$ROOT_DIR/../crystal/src" && pwd -P)"
else
  echo "set CRYSTAL_PATH to the external Crystal stdlib source directory" >&2
  exit 2
fi
[[ -x "$SAFE_RUNNER" && -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -d "$CRYSTAL_STDLIB" ]] || exit 2

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reference-wrapper-owner.XXXXXX")"
cleanup() {
  local status=$?
  for name in direct_yielded lexical siblings; do
    rm -rf "$WORK_DIR/original-$name.cache" "$WORK_DIR/candidate-$name.cache"
  done
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/direct_yielded.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

class Reference
end

abstract class OutputSink
end

class OutputBuffer < OutputSink
end

class FormatBuilder
  def self.with(sink : OutputSink, &)
    yield new
  end
end

class Object
  def emit_format_direct(sink : OutputSink)
    emit_format_direct(FormatBuilder.new)
  end

  def emit_format_yielded(sink : OutputSink)
    FormatBuilder.with(sink) do |builder|
      emit_format_yielded(builder)
    end
  end
end

class FormattedMessage < Reference
  def emit_format_direct(builder : FormatBuilder)
    C.putchar(65)
  end

  def emit_format_yielded(builder : FormatBuilder)
    C.putchar(65)
  end
end

message = FormattedMessage.new
message.emit_format_direct(OutputBuffer.new)
message.emit_format_yielded(OutputBuffer.new)
message.emit_format_direct(FormatBuilder.new)
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/direct_yielded.expected" <<'EXPECTED'
AAA
EXPECTED
: >"$WORK_DIR/direct_yielded.stderr.expected"

cat >"$WORK_DIR/lexical.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

class Reference
end

abstract class OutputSink
end

class OutputBuffer < OutputSink
end

class FormatBuilder
  def self.with(sink : OutputSink, &)
    yield new
  end
end

class Token
end

class Object
  def select_lexical(sink : OutputSink)
    select_lexical(Token.new)
  end
end

module CallerScope
  class Token
  end

  class FormattedMessage < Reference
    def select_lexical(token : ::Token)
      C.putchar(65)
    end
  end
end

CallerScope::FormattedMessage.new.select_lexical(OutputBuffer.new)
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/lexical.expected" <<'EXPECTED'
A
EXPECTED
: >"$WORK_DIR/lexical.stderr.expected"

cat >"$WORK_DIR/siblings.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

class Reference
end

abstract class OutputSink
end

class OutputBuffer < OutputSink
end

class FormatBuilder
  def self.with(sink : OutputSink, &)
    yield new
  end
end

class Object
  def emit_format_direct(sink : OutputSink)
    emit_format_direct(FormatBuilder.new)
  end

  def emit_format_yielded(sink : OutputSink)
    FormatBuilder.with(sink) do |builder|
      emit_format_yielded(builder)
    end
  end
end

class FormattedMessage < Reference
  def emit_format_direct(builder : FormatBuilder)
    C.putchar(65)
  end

  def emit_format_yielded(builder : FormatBuilder)
    C.putchar(65)
  end
end

class OtherMessage < Reference
  def emit_format_direct(builder : FormatBuilder)
    C.putchar(66)
  end

  def emit_format_yielded(builder : FormatBuilder)
    C.putchar(66)
  end
end

first = FormattedMessage.new
second = OtherMessage.new
first.emit_format_direct(OutputBuffer.new)
second.emit_format_direct(OutputBuffer.new)
first.emit_format_yielded(OutputBuffer.new)
second.emit_format_yielded(OutputBuffer.new)
message = FormattedMessage.new
message.emit_format_direct(OutputBuffer.new)
message.emit_format_yielded(OutputBuffer.new)
message.emit_format_direct(FormatBuilder.new)
C.putchar(10)
CRYSTAL
cat >"$WORK_DIR/siblings.expected" <<'EXPECTED'
ABABAAA
EXPECTED
: >"$WORK_DIR/siblings.stderr.expected"

compile_run() {
  local name="$1" mode="$2" compiler="$3" status=0
  local source="$WORK_DIR/$name.cr" output="$WORK_DIR/$mode-$name.bin"
  local log="$WORK_DIR/$mode-$name.compile.log" cache="$WORK_DIR/$mode-$name.cache"
  if [[ "$mode" == original ]]; then
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 build "$source" --no-debug \
      --link-flags=-fuse-ld=/usr/bin/ld -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    if env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
      ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
      RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.compile.resources" \
      "$SAFE_RUNNER" "$compiler" 180 8192 "$source" --no-ast-cache --no-llvm-cache \
      --no-debug --no-prelude -o "$output" >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL[$mode/$name]: compile exited $status" >&2
    tail -30 "$log" >&2
    return 1
  fi
  if ! RUN_SAFE_PASSTHROUGH_STDIO=1 \
    RUN_SAFE_RESOURCE_FILE="$WORK_DIR/$mode-$name.run.resources" \
    "$SAFE_RUNNER" "$output" 10 512 >"$WORK_DIR/$mode-$name.stdout" \
    2>"$WORK_DIR/$mode-$name.run.log"; then
    echo "FAIL[$mode/$name]: runtime failed" >&2
    cat "$WORK_DIR/$mode-$name.run.log" >&2
    return 1
  fi
  grep -Fq '[EXIT: 0]' "$WORK_DIR/$mode-$name.run.log"
  diff -u "$WORK_DIR/$name.expected" "$WORK_DIR/$mode-$name.stdout"
  awk '/^=== STDERR ===$/ { capture=1; next } /^\[EXIT: / { capture=0 } capture { print }' \
    "$WORK_DIR/$mode-$name.run.log" >"$WORK_DIR/$mode-$name.stderr"
  diff -u "$WORK_DIR/$name.stderr.expected" "$WORK_DIR/$mode-$name.stderr"
}

# Certify every fixture against the original before testing the candidate.
for name in direct_yielded lexical siblings; do
  compile_run "$name" original "$ORIGINAL_CRYSTAL_BIN"
done
for name in direct_yielded lexical siblings; do
  compile_run "$name" candidate "$COMPILER"
  echo "PASS[$name]: original and candidate stdout and stderr agree"
done
echo "PASS[reference-wrapper-owner]: three original-first fixtures agree"
