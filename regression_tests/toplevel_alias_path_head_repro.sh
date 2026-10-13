#!/usr/bin/env bash
# A top-level `alias HIR = A::HIR` registers `HIR` as a top-level type name, so
# the type-name resolver treated `HIR::Call` as anchored at the top level and
# kept it as an unregistered phantom type (distinct from `A::HIR::Call`).
# is_a?/case narrowing and `.as(HIR::Call?)` then targeted the phantom and the
# yielding method on the phantom receiver was emitted as an abort stub.
# Crystal resolves the alias head like any path head: a lexically visible
# nested type first, otherwise the alias target.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/toplevel_alias_path_head.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cat >"$WORK_DIR/np_alias.cr" <<'CR'
lib LibC
  fun exit(status : Int32) : NoReturn
end
alias HIR = A::HIR
module A
  module HIR
    class Inst
    end
    class Call < Inst
      def initialize(@code : Int32)
      end
      def code : Int32
        @code
      end
    end
    class Other < Inst
    end
    class Pair
      def initialize(@a : Inst, @b : Inst)
      end
      def each
        yield @a
        yield @b
      end
    end
  end
  module C
    class CLI
      def scan(p : HIR::Pair) : Int32
        found = 0
        p.each do |inst|
          if inst.is_a?(HIR::Other)
            next
          elsif inst.is_a?(HIR::Call) && inst.code > 3
            found = inst.code
            break
          end
        end
        found
      end

      def narrow(v : HIR::Inst, flag : Int32?) : Int32
        if flag && v.is_a?(HIR::Call)
          return v.code
        end
        0
      end

      def cast_local(p : HIR::Pair) : Int32
        hit = nil.as(HIR::Call?)
        p.each do |inst|
          case inst
          when HIR::Call
            hit = inst
            break
          end
        end
        return 0 unless h = hit
        h.code
      end
    end
  end
  module D
    module HIR
      class Call
        def code : Int32
          40
        end
      end
    end
    class Shadow
      # The lexically visible A::D::HIR wins over the top-level alias.
      def run : Int32
        HIR::Call.new.code
      end
    end
  end
end
p = A::HIR::Pair.new(A::HIR::Other.new, A::HIR::Call.new(9))
cli = A::C::CLI.new
LibC.exit(1) unless cli.scan(p) == 9
LibC.exit(2) unless cli.narrow(A::HIR::Call.new(9), 1) == 9
LibC.exit(3) unless cli.cast_local(p) == 9
LibC.exit(4) unless HIR::Call.new(7).code == 7
LibC.exit(5) unless A::D::Shadow.new.run == 40
LibC.exit(0)
CR
if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
    "$WORK_DIR/np_alias.cr" --no-prelude -o "$WORK_DIR/np_alias" >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/np_alias" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  grep -E '^\[EXIT|STUB' "$WORK_DIR/run.log" >&2 || cat "$WORK_DIR/run.log" >&2
  exit 1
fi
echo toplevel_alias_path_head_repro_ok
