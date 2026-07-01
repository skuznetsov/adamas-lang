#!/usr/bin/env bash
# Frontend command-call contract guard: no-parens command calls must preserve a
# parenthesized member-access argument as the argument, not as member access on
# the command-call result.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECT_MISMATCH="${ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH:-0}"
TIMEOUT_SECS="${COMMAND_CALL_MEMBER_TIMEOUT:-5}"
MAX_MEM_MB="${COMMAND_CALL_MEMBER_MAX_MEM:-512}"

mkdir -p "$ROOT_DIR/tmp"
WORKDIR="$(mktemp -d "$ROOT_DIR/tmp/command_call_member_access.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

PROBE="$WORKDIR/command_call_member_access_probe.cr"
BIN="$WORKDIR/command_call_member_access_probe"
BUILD_LOG="$WORKDIR/build.log"
RUN_LOG="$WORKDIR/run.log"

cat >"$PROBE" <<'CRYSTAL'
require "../../src/compiler/frontend/parser"

alias Frontend = Adamas::Compiler::Frontend

private def parse_roots(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  parser.parse_program
end

private def member_name(arena, node)
  return nil unless node.is_a?(Frontend::MemberAccessNode)
  String.new(node.member)
end

private def assert_command_arg_member(source : String, root_index : Int32 = 0)
  program = parse_roots(source)
  arena = program.arena
  root = arena[program.roots[root_index]]

  unless root.is_a?(Frontend::CallNode)
    STDERR.puts "expected command call root, got #{root.class.name} for #{source.inspect}"
    exit 1
  end
  unless root.args.size == 1
    STDERR.puts "expected one command argument, got #{root.args.size} for #{source.inspect}"
    exit 1
  end

  arg = arena[root.args.first]
  unless arg.is_a?(Frontend::MemberAccessNode) && member_name(arena, arg) == "class"
    STDERR.puts "expected .class as the command argument, got #{arg.class.name} for #{source.inspect}"
    exit 1
  end
end

private def assert_command_arg_ternary(source : String)
  program = parse_roots(source)
  arena = program.arena
  root = arena[program.roots.first]

  unless root.is_a?(Frontend::CallNode)
    STDERR.puts "expected command call root, got #{root.class.name} for #{source.inspect}"
    exit 1
  end
  unless root.args.size == 1
    STDERR.puts "expected one command argument, got #{root.args.size} for #{source.inspect}"
    exit 1
  end
  arg = arena[root.args.first]
  unless arg.is_a?(Frontend::TernaryNode)
    STDERR.puts "expected ternary command argument without .class, got #{arg.class.name} for #{source.inspect}"
    exit 1
  end
end

assert_command_arg_member("puts (true ? 1 : nil).class")
assert_command_arg_member("puts((true ? 1 : nil).class)")
assert_command_arg_member("x = true ? 1 : nil\nputs x.class", 1)
assert_command_arg_ternary("puts (true ? 1 : nil)")

puts "command_call_member_access_preservation_ok"
CRYSTAL

if ! crystal build "$PROBE" -o "$BIN" --error-trace >"$BUILD_LOG" 2>&1; then
  echo "command-call member-access guard: probe build failed" >&2
  tail -n 80 "$BUILD_LOG" >&2 || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" "$TIMEOUT_SECS" "$MAX_MEM_MB" >"$RUN_LOG" 2>&1
probe_rc=$?
set -e

if [[ $probe_rc -eq 0 ]]; then
  if [[ "$EXPECT_MISMATCH" == "1" ]]; then
    echo "expected command-call member-access mismatch, but guard passed" >&2
    cat "$RUN_LOG" >&2
    exit 1
  fi
  cat "$RUN_LOG"
  exit 0
fi

echo "command-call member-access preservation mismatch" >&2
tail -n 80 "$RUN_LOG" >&2 || true

if [[ "$EXPECT_MISMATCH" == "1" ]]; then
  echo "MEASURED_RED: command-call member-access preservation mismatch reproduced"
  exit 0
fi

exit 1
