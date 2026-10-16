#!/usr/bin/env bash
# Exact enum owners must outrank unrelated module suffixes in value dispatch.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enum-nominal-module.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    printf 'kept_tmp=%s\n' "$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/probe.cr" <<'CRYSTAL'
lib NominalEnumC
  fun putchar(value : Int32) : Int32
end

module EnumDomain
  enum Options : UInt32
    One = 1
    def probe : Int32
      65
    end
  end
end

module OtherDomain
  enum Options : UInt32
    Two = 2
    def probe : Int32
      66
    end
  end
end

module Collision
  class Config
    module Options
      def probe : Int32
        73
      end
    end
    include Options
  end
end

struct UInt32
  def probe : Int32
    67
  end
end

alias OptionsAlias = EnumDomain::Options

def enum_probe(value : EnumDomain::Options) : Int32
  value.probe
end

def alias_probe(value : OptionsAlias) : Int32
  value.probe()
end

def other_probe(value : OtherDomain::Options) : Int32
  value.probe
end

def module_probe(value : Collision::Config::Options) : Int32
  value.probe()
end

def underlying_probe(value : EnumDomain::Options) : Int32
  value.value.probe
end

NominalEnumC.putchar(enum_probe(EnumDomain::Options::One))
NominalEnumC.putchar(alias_probe(EnumDomain::Options::One))
NominalEnumC.putchar(other_probe(OtherDomain::Options::Two))
NominalEnumC.putchar(module_probe(Collision::Config.new))
NominalEnumC.putchar(underlying_probe(EnumDomain::Options::One))
NominalEnumC.putchar(10)
CRYSTAL

if ! ADAMAS_LLVM_CACHE=0 RUN_SAFE_RESOURCE_FILE="$WORK_DIR/build.resources.json" \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 "$WORK_DIR/probe.cr" \
  --no-prelude --no-ast-cache --no-llvm-cache --no-debug -o "$WORK_DIR/probe" \
  >"$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2
  exit 1
fi
if ! RUN_SAFE_RESOURCE_FILE="$WORK_DIR/run.resources.json" \
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/probe" 5 512 >"$WORK_DIR/run.log" 2>&1; then
  cat "$WORK_DIR/run.log" >&2
  exit 1
fi
actual="$(sed -n '/^=== STDOUT ===$/,/^=== STDERR ===$/{/^=== STDOUT ===$/d;/^=== STDERR ===$/d;p;}' "$WORK_DIR/run.log")"
if [[ "$actual" != 'AABIC' ]] || ! grep -Fq '[EXIT: 0]' "$WORK_DIR/run.log"; then
  cat "$WORK_DIR/run.log" >&2
  printf 'unexpected enum, alias, module, or integer dispatch\n' >&2
  exit 1
fi
printf 'PASS: nominal enum dispatch before module suffix recovery\n'
