#!/usr/bin/env bash
# Regression: a forwarded Enumerable(String) value must match its exact module
# annotation when selecting the blockful initializer used by Process.new's
# nested callback path. Scalar String must still fail an Enumerable restriction.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/process_nested_callback_constructor_repro.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/mini_process.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end

class File
  class Error
    def self.from_os_error(message : String, error : Int32, file : String) : Nil
      error
    end
  end
end

class IO
end

struct Path
end

alias Env = Nil | Hash(String, Nil) | Hash(String, String?) | Hash(String, String)

module Enumerable(T)
end

module TestSystem
  def self.spawn(args : Enumerable(String), &) : Int32
    yield 0, "fake-command"
    41
  end
end

class MiniProcess
  enum Redirect
    Close
    Pipe
    Inherit
  end

  alias Stdio = Redirect | IO

  @which : Int32

  def self.new(args : Enumerable(String), *, env : Env = nil, clear_env : Bool = false,
               input : Stdio = MiniProcess::Redirect::Close, output : Stdio = MiniProcess::Redirect::Close, error : Stdio = MiniProcess::Redirect::Close,
               chdir : Path | String? = nil)
    new(args, env: env, clear_env: clear_env, input: input, output: output, error: error, chdir: chdir) do |status, command|
      File::Error.from_os_error("Error executing process", status, command)
    end
  end

  protected def initialize(args : Enumerable(String), *, env : Env = nil, clear_env : Bool = false,
                           input : Stdio = MiniProcess::Redirect::Close, output : Stdio = MiniProcess::Redirect::Close, error : Stdio = MiniProcess::Redirect::Close,
                           chdir : Path | String? = nil, &)
    pid = TestSystem.spawn(args) do |status, command|
      yield status, command
    end
    @which = pid
  end

  def initialize(command : String, args : Enumerable(String)? = nil, env : Env = nil, clear_env : Bool = false,
                 shell : Bool = false, input : Stdio = MiniProcess::Redirect::Close, output : Stdio = MiniProcess::Redirect::Close,
                 error : Stdio = MiniProcess::Redirect::Close, chdir : Path | String? = nil)
    @which = 2
  end

  def which
    @which
  end
end

forwarded = MiniProcess.new(["cmd"], output: MiniProcess::Redirect::Inherit)
string_ctor = MiniProcess.new("cmd")
LibC.exit(forwarded.which == 41 && string_ctor.which == 2 ? 0 : 1)
CR

cat >"$WORK_DIR/module_mismatch.cr" <<'CR'
module Enumerable(T)
end

def take_strings(items : Enumerable(String))
  items
end

take_strings("not enumerable")
CR

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/mini_process.cr" --no-prelude -o "$WORK_DIR/mini_process" \
    >"$WORK_DIR/mini_process.build.log" 2>&1; then
  echo "FAIL: MiniProcess nested-callback fixture did not compile" >&2
  tail -30 "$WORK_DIR/mini_process.build.log" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/mini_process" 5 512 \
  >"$WORK_DIR/mini_process.run.log" 2>&1 || true
if ! grep -q '^\[EXIT: 0\]' "$WORK_DIR/mini_process.run.log"; then
  echo "FAIL: forwarded Enumerable callback or String constructor control failed" >&2
  cat "$WORK_DIR/mini_process.run.log" >&2
  exit 1
fi

if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 600 8192 \
    "$WORK_DIR/module_mismatch.cr" --no-prelude -o "$WORK_DIR/module_mismatch" \
    >"$WORK_DIR/module_mismatch.build.log" 2>&1; then
  echo "FAIL: module-mismatch fixture did not compile" >&2
  tail -30 "$WORK_DIR/module_mismatch.build.log" >&2
  exit 1
fi
"$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/module_mismatch" 5 512 \
  >"$WORK_DIR/module_mismatch.run.log" 2>&1 || true
if ! grep -q '^STUB CALLED: take_strings\$String$' "$WORK_DIR/module_mismatch.run.log"; then
  echo "FAIL: String satisfied the Enumerable(String) restriction" >&2
  tail -30 "$WORK_DIR/module_mismatch.build.log" >&2
  cat "$WORK_DIR/module_mismatch.run.log" >&2
  exit 1
fi

echo "PASS: exact Enumerable forwarding accepted; String constructor and scalar mismatch controls preserved"
