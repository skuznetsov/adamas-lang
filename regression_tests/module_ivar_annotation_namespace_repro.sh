#!/usr/bin/env bash
# An ivar declared in an included module (`property data : Loop::Ar::Idx` in
# Cr::Sys) is spelled in the module's lexical scope. The includer layout pass
# re-resolved that spelling under the includer (Wrap::Host), so a generic path
# head became the phantom Wrap::Host::Loop::Ar::Idx, and an includer-side type
# with the same path shadowed the module's. The includer's own ivar with the
# same spelling must keep resolving in the includer's scope (lookup caches
# keyed without the namespace leaked one resolution into the other). Prelude hello hits this through
# `property __evloop_data : EventLoop::Polling::Arena::Index` in
# Crystal::System::FileDescriptor, included by IO::FileDescriptor.
# An unresolvable spelling must still be rejected.
#
# Usage: ADAMAS_BIN=path/to/adamas [CRYSTAL_BIN=path/to/original/crystal] $0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
CRYSTAL_BIN="${CRYSTAL_BIN:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/module-ivar-annotation-namespace.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$WORK_DIR/header.cr" <<'CR'
@[Link("gc", pkg_config: "bdw-gc")]
lib LibGC
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(99)
end

class Object
  macro property(*names, &block)
    {% for name in names %}
      {% var_name = name.var.id %}
      {% type = name.type %}
      @{{name}}

      def {{var_name}} : {{type}}
        @{{var_name}}
      end

      def {{var_name}}=(@{{var_name}} : {{type}})
      end
    {% end %}
  end
end

module Cr
  class Loop
    class Ar(T)
      struct Idx
        def initialize(@v : Int32)
        end

        def v : Int32
          @v
        end
      end

      INVALID = Idx.new(-1)
    end

    def take(i : Ar::Idx) : Int32
      i.v
    end
  end
end

module Cr::Sys
end

module Wrap
  class Host
    include Cr::Sys
  end
end

module Cr::Sys
  property data : Loop::Ar::Idx = Loop::Ar::INVALID
end
CR

SHADOW_CR='module Wrap
  module Loop
    class Ar(T)
      struct Idx
        def initialize(@v : Int32)
        end

        def v : Int32
          9
        end
      end
    end
  end
end
'

{ cat "$WORK_DIR/header.cr"; printf 'h = Wrap::Host.new\nh.data = Cr::Loop::Ar::Idx.new(4)\nLibC.exit(Cr::Loop.new.take(h.data))\n'; } > "$WORK_DIR/generic_owner_nested_type.cr"
{ cat "$WORK_DIR/header.cr"; printf '%s\nh = Wrap::Host.new\nh.data = Cr::Loop::Ar::Idx.new(5)\nLibC.exit(h.data.v)\n' "$SHADOW_CR"; } > "$WORK_DIR/includer_namespace_shadow.cr"
{ cat "$WORK_DIR/header.cr"; printf '%s\nmodule Wrap\n  class Host\n    property own : Loop::Ar::Idx = Loop::Ar::Idx.new(1)\n  end\nend\n\nh = Wrap::Host.new\nh.data = Cr::Loop::Ar::Idx.new(5)\nh.own = Wrap::Loop::Ar::Idx.new(3)\nLibC.exit(h.data.v * 10 + h.own.v)\n' "$SHADOW_CR"; } > "$WORK_DIR/includer_own_same_spelling.cr"
{ sed 's/property data : Loop::Ar::Idx/property data : Loop::Nope::Idx/' "$WORK_DIR/header.cr"
  printf 'h = Wrap::Host.new\nh.data = Cr::Loop::Ar::Idx.new(4)\nLibC.exit(Cr::Loop.new.take(h.data))\n'; } > "$WORK_DIR/unresolvable_annotation.cr"

POSITIVE_CASES=(generic_owner_nested_type:4 includer_namespace_shadow:5 includer_own_same_spelling:59)
NEGATIVE_CASE=unresolvable_annotation
exit_code_of() {
  grep -o '\[EXIT: [0-9]*\]' "$1" | head -1 | tr -dc '0-9'
}

# Original Crystal first, so the fixtures themselves are qualified.
if [[ -n "$CRYSTAL_BIN" ]]; then
  for entry in "${POSITIVE_CASES[@]}"; do
    name="${entry%%:*}"
    expected="${entry##*:}"
    if ! CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
        "$WORK_DIR/$name.cr" -o "$WORK_DIR/$name.orig" > "$WORK_DIR/$name.orig.log" 2>&1; then
      printf 'ORACLE FAIL: original rejects %s\n' "$name" >&2
      cat "$WORK_DIR/$name.orig.log" >&2
      exit 2
    fi
    "$SAFE_RUNNER" "$WORK_DIR/$name.orig" 5 256 > "$WORK_DIR/$name.orig.run" 2>&1 || true
    if [[ "$(exit_code_of "$WORK_DIR/$name.orig.run")" != "$expected" ]]; then
      printf 'ORACLE FAIL: original %s did not exit %s\n' "$name" "$expected" >&2
      exit 2
    fi
  done
  if CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$CRYSTAL_BIN" build --prelude=empty \
      "$WORK_DIR/$NEGATIVE_CASE.cr" -o "$WORK_DIR/$NEGATIVE_CASE.orig" > "$WORK_DIR/$NEGATIVE_CASE.orig.log" 2>&1 ||
      ! grep -qF "undefined constant Loop::Nope::Idx" "$WORK_DIR/$NEGATIVE_CASE.orig.log"; then
    printf 'ORACLE FAIL: original does not reject %s\n' "$NEGATIVE_CASE" >&2
    exit 2
  fi
fi

failures=0

for entry in "${POSITIVE_CASES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  log="$WORK_DIR/$name.adamas.log"
  "$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$name.cr" \
    -o "$WORK_DIR/$name.adamas" > "$log" 2>&1 || true
  if [[ "$(exit_code_of "$log")" != "0" ]]; then
    printf 'FAIL positive %s (compile exit %s): %s\n' "$name" "$(exit_code_of "$log")" \
      "$(grep -m1 -i 'error\|invalid memory' "$log" || tail -1 "$log")"
    failures=$((failures + 1))
    continue
  fi
  run_log="$WORK_DIR/$name.adamas.run"
  "$SAFE_RUNNER" "$WORK_DIR/$name.adamas" 5 256 > "$run_log" 2>&1 || true
  if [[ "$(exit_code_of "$run_log")" == "$expected" ]]; then
    printf 'PASS positive %s\n' "$name"
  else
    printf 'FAIL positive %s (run): exit %s, expected %s\n' "$name" "$(exit_code_of "$run_log")" "$expected"
    failures=$((failures + 1))
  fi
done

log="$WORK_DIR/$NEGATIVE_CASE.adamas.log"
"$SAFE_RUNNER" "$ADAMAS_BIN" 120 4096 --prelude=empty "$WORK_DIR/$NEGATIVE_CASE.cr" \
  -o "$WORK_DIR/$NEGATIVE_CASE.adamas" > "$log" 2>&1 || true
if [[ "$(exit_code_of "$log")" == "1" ]] && grep -qi "error" "$log" &&
    [[ ! -e "$WORK_DIR/$NEGATIVE_CASE.adamas" ]]; then
  printf 'PASS negative %s\n' "$NEGATIVE_CASE"
else
  printf 'FAIL negative %s (exit %s): %s\n' "$NEGATIVE_CASE" "$(exit_code_of "$log")" \
    "$(grep -m1 -i 'error' "$log" || tail -1 "$log")"
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  printf '%d module ivar annotation namespace case(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'module ivar annotation namespace cases passed\n'
