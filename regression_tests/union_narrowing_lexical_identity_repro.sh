#!/usr/bin/env bash
# Lexical identity must survive union narrowing when an inline yielding method
# reuses a nominal name that also exists in the callee's namespace.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
CRYSTAL_LIB="${CRYSTAL_LIBRARY_PATH:-/opt/homebrew/lib}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/union-narrowing-lexical-identity.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL_CRYSTAL" || ! -x "$CANDIDATE" ]]; then
  echo "ERROR: safe runner, original Crystal, and candidate compiler must be executable" >&2
  exit 2
fi

write_prefix() {
  local nested_path_kind="${1:-module}"
  cat <<'CRYSTAL'
lib LexicalIdentityC
  fun exit(status : Int32) : NoReturn
  fun getpid : Int32
end

class Path
end

module Crystal
  module System
CRYSTAL
  if [[ "$nested_path_kind" == class ]]; then
    cat <<'CRYSTAL'
    class Path
    end
CRYSTAL
  else
    cat <<'CRYSTAL'
    module Path
    end
CRYSTAL
  fi
  cat <<'CRYSTAL'
  end
end

class Target
  def self.cd(value : Path | String) : Int32
    42
  end

  def self.cd(value : Path | String, &)
    cd(value)
    yield
  end
end
CRYSTAL
}

write_case() {
  local name="$1"
  local body="$2"
  local nested_path_kind="${3:-module}"
  local source="$WORK_DIR/$name.cr"
  write_prefix "$nested_path_kind" >"$source"
  cat >>"$source" <<<"$body"
}

write_case inline_truthy_guard "$(cat <<'CRYSTAL'
module Crystal::System::Process
  def self.replace(value)
    if value
      ::Target.cd(value) { 42 }
    else
      0
    end
  end
end

class Process
  def self.exec(value : Path | String? = nil)
    Crystal::System::Process.replace(value)
  end
end

value = LexicalIdentityC.getpid > 0 ? Path.new : (LexicalIdentityC.getpid < 0 ? "." : nil)
LexicalIdentityC.exit(
  Process.exec(value) == 42 &&
  Process.exec(".") == 42 &&
  Process.exec(nil) == 0 ? 0 : 1
)
CRYSTAL
)"

write_case inline_not_nil_arms "$(cat <<'CRYSTAL'
class Object
  def not_nil!
    self
  end
end

struct Nil
  def not_nil! : NoReturn
    LexicalIdentityC.exit(91)
  end
end

module Crystal::System::Process
  def self.replace(value)
    ::Target.cd(value.not_nil!) { 42 }
  end
end

class Process
  def self.exec(value : Path | String? = nil)
    Crystal::System::Process.replace(value)
  end
end

value = LexicalIdentityC.getpid > 0 ? Path.new : (LexicalIdentityC.getpid < 0 ? "." : nil)
LexicalIdentityC.exit(
  Process.exec(value) == 42 &&
  Process.exec(Path.new) == 42 &&
  Process.exec(".") == 42 ? 0 : 1
)
CRYSTAL
)"

write_case no_inline_control "$(cat <<'CRYSTAL'
module Crystal::System::Process
  def self.replace(value)
    if value
      ::Target.cd(value)
    else
      0
    end
  end
end

class Process
  def self.exec(value : Path | String? = nil)
    Crystal::System::Process.replace(value)
  end
end

value = LexicalIdentityC.getpid > 0 ? Path.new : (LexicalIdentityC.getpid < 0 ? "." : nil)
LexicalIdentityC.exit(
  Process.exec(value) == 42 &&
  Process.exec(".") == 42 &&
  Process.exec(nil) == 0 ? 0 : 1
)
CRYSTAL
)"

write_case wrong_nested_path "$(cat <<'CRYSTAL'
Target.cd(Crystal::System::Path.new)
CRYSTAL
)" class

compile_case() {
  local stage="$1" compiler="$2" name="$3" mode="$4"
  local source="$WORK_DIR/$name.cr"
  local binary="$WORK_DIR/$stage-$name"
  local log="$WORK_DIR/$stage-$name.log"
  local cache="$WORK_DIR/$stage-$name.cache"
  local status=0
  mkdir -p "$cache"

  if [[ "$stage" == original ]]; then
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_LIBRARY_PATH="$CRYSTAL_LIB" \
      CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$compiler" 120 4096 build --prelude=empty --no-debug \
      "$source" -o "$binary" >"$log" 2>&1 || status=$?
  else
    env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_LIBRARY_PATH="$CRYSTAL_LIB" \
      CRYSTAL_CACHE_DIR="$cache" ADAMAS_LLVM_CACHE=0 \
      "$SAFE_RUNNER" "$compiler" 120 4096 "$source" --no-prelude \
      --no-debug --no-ast-cache --no-llvm-cache -o "$binary" \
      >"$log" 2>&1 || status=$?
  fi

  if [[ "$mode" == reject ]]; then
    if [[ "$status" == 0 ]] || \
      ! rg -q "no overload matches|expected argument" "$log" || \
      ! rg -q "Crystal::System::Path" "$log"; then
      cat "$log" >&2
      echo "FAIL $stage $name: expected nested Path to miss the root Path overload" >&2
      return 1
    fi
    printf 'PASS %s %s rejected nested nominal Path\n' "$stage" "$name"
    return 0
  fi

  if [[ "$status" != 0 ]]; then
    cat "$log" >&2
    echo "FAIL $stage $name: compile failed" >&2
    return 1
  fi

  status=0
  "$SAFE_RUNNER" "$binary" 5 512 >"$log" 2>&1 || status=$?
  if [[ "$status" != 0 ]] || ! rg -Fq '[EXIT: 0]' "$log"; then
    cat "$log" >&2
    echo "FAIL $stage $name: native run did not exit zero" >&2
    return 1
  fi
  printf 'PASS %s %s compile-and-run exit=0\n' "$stage" "$name"
}

positive_cases=(inline_truthy_guard inline_not_nil_arms no_inline_control)

# Qualify the source and expected rejection against installed Crystal first.
for name in "${positive_cases[@]}"; do
  compile_case original "$ORIGINAL_CRYSTAL" "$name" allow
done
compile_case original "$ORIGINAL_CRYSTAL" wrong_nested_path reject

candidate_failures=0
for name in no_inline_control inline_truthy_guard inline_not_nil_arms; do
  compile_case candidate "$CANDIDATE" "$name" allow || candidate_failures=1
done
compile_case candidate "$CANDIDATE" wrong_nested_path reject || candidate_failures=1

if [[ "$candidate_failures" != 0 ]]; then
  echo "FAIL: candidate disagreed with Crystal on lexical union identity cases" >&2
  exit 1
fi

printf 'PASS: lexical union identity matches Crystal for truthy, not_nil!, no-inline, and nested-Path rejection cases\n'
