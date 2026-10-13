#!/usr/bin/env bash
# Regression: struct ivar typed only by a class-method call result.
# `struct Inner; def initialize(@pid); @ch = Handler.wait(@pid)` with an
# annotated `def self.wait(pid : Int32) : Box`. Registration-time ivar
# guessing returned Void for any non-`new` call, so Inner was laid out
# without @ch (size 8) while Outer inlined it; lowering later grew Inner to
# 16, and Outer's next field (@wc) overlapped Inner's tail. Original Crystal
# guesses the ivar from the class method's return annotation
# (`guess_type_from_class_method`). Original-stdlib Process hit this:
# `@channel = SignalChildHandler.wait(@pid)` overlapped `@wait_count` →
# "BUG: Notification channel was not initialized".
# Cases: module declared before/after the struct, forward struct decl,
# namespaced owner with a generic return annotation, and an inherited
# class method with and without call parens. Each prints EXIT 7.
# Path-named (`struct Crystal::System::Process`) and nested-module structs
# register inside the Pass 1 modules loop, before a later module's class
# methods are registered; the guess falls back to the scoped-macro prescan
# index of class-method defs (exact owner only).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/struct_ivar_call_return.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/module_before.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Box
end
module Handler
  def self.wait(pid : Int32) : Box
    Box.new
  end
end
class Outer
  @info : Inner
  @wc = 0
  def initialize(pid : Int32)
    @info = Inner.new(pid)
  end
  def wc
    @wc
  end
end
struct Inner
  def initialize(@pid : Int32)
    @ch = Handler.wait(@pid)
  end
end
o = Outer.new(5)
LibC.exit(o.wc == 0 ? 7 : 40)
CR

cat >"$WORK_DIR/forward_struct.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Box
end
module Handler
  def self.wait(pid : Int32) : Box
    Box.new
  end
end
struct Inner
end
class Outer
  @info : Inner
  @wc = 0
  def initialize(pid : Int32)
    @info = Inner.new(pid)
  end
  def wc
    @wc
  end
end
struct Inner
  def initialize(@pid : Int32)
    @ch = Handler.wait(@pid)
  end
end
o = Outer.new(5)
LibC.exit(o.wc == 0 ? 7 : 40)
CR

cat >"$WORK_DIR/module_after.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Box
end
class Outer
  @info : Inner
  @wc = 0
  def initialize(pid : Int32)
    @info = Inner.new(pid)
  end
  def wc
    @wc
  end
end
struct Inner
  def initialize(@pid : Int32)
    @ch = Handler.wait(@pid)
  end
end
module Handler
  def self.wait(pid : Int32) : Box
    Box.new
  end
end
o = Outer.new(5)
LibC.exit(o.wc == 0 ? 7 : 40)
CR

cat >"$WORK_DIR/namespaced_generic_return.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Chan(T)
  @v : T
  def initialize(@v : T)
  end
end
module Sys
  class Box
    @a = 1
    @b = 2
  end
  module Handler
    def self.wait(pid : Int32) : Chan(Int32)
      Chan(Int32).new(pid)
    end
    def self.mk : Box
      Box.new
    end
  end
  struct Inner
    def initialize(@pid : Int32)
      @ch = Handler.wait(@pid)
      @bx = Sys::Handler.mk
    end
  end
  class Outer
    @info : Inner
    @wc = 0
    def initialize(pid : Int32)
      @info = Inner.new(pid)
    end
    def wc
      @wc
    end
  end
end
o = Sys::Outer.new(5)
LibC.exit(o.wc == 0 ? 7 : 40)
CR

cat >"$WORK_DIR/inherited_class_method.cr" <<'CR'
lib LibC
  fun exit(code : Int32) : NoReturn
end
class Box
end
class Base
  def self.make(x : Int32) : Box
    Box.new
  end
end
class Derived < Base
end
struct Inner
  def initialize(@pid : Int32)
    @ch = Derived.make(@pid)
    @nb = Derived.make @pid
  end
end
class Outer
  @info : Inner
  @wc = 0
  def initialize(pid : Int32)
    @info = Inner.new(pid)
  end
  def wc
    @wc
  end
end
o = Outer.new(5)
LibC.exit(o.wc == 0 ? 7 : 40)
CR

cat >"$WORK_DIR/path_named_later_module.cr" <<'CR'
lib LibC
  alias PidT = Int32
  fun exit(code : Int32) : NoReturn
end
class Chan(T)
  @v : T
  def initialize(@v : T)
  end
end
module Crystal
  module System
  end
end
class Outer
  @info : Crystal::System::Process
  @wc = 0
  def initialize(pid : Int32)
    @info = Crystal::System::Process.new(pid)
  end
  def wc
    @wc
  end
end
struct Crystal::System::Process
  getter pid : LibC::PidT
  def initialize(@pid : LibC::PidT)
    @channel = SCH.wait(@pid)
  end
end
module SCH
  def self.wait(pid : LibC::PidT) : Chan(Int32)
    Chan(Int32).new(pid)
  end
end
o = Outer.new(5)
LibC.exit(o.wc == 0 ? 7 : 40)
CR

cat >"$WORK_DIR/path_named_namespaced_handler.cr" <<'CR'
lib LibC
  alias PidT = Int32
  fun exit(code : Int32) : NoReturn
end
class Chan(T)
  @v : T
  def initialize(@v : T)
  end
end
module Crystal
  module System
  end
end
class Outer
  @info : Crystal::System::Process
  @wc = 0
  def initialize(pid : Int32)
    @info = Crystal::System::Process.new(pid)
  end
  def wc
    @wc
  end
end
struct Crystal::System::Process
  getter pid : LibC::PidT
  def initialize(@pid : LibC::PidT)
    @channel = Crystal::System::SignalChildHandler.wait(@pid)
  end
end
module Crystal::System::SignalChildHandler
  def self.wait(pid : LibC::PidT) : Chan(Int32)
    Chan(Int32).new(pid)
  end
end
o = Outer.new(5)
LibC.exit(o.wc == 0 ? 7 : 40)
CR

cat >"$WORK_DIR/nested_module_later_module.cr" <<'CR'
lib LibC
  alias PidT = Int32
  fun exit(code : Int32) : NoReturn
end
class Chan(T)
  @v : T
  def initialize(@v : T)
  end
end
module Crystal
  module System
  end
end
class Outer
  @info : Crystal::System::Process
  @wc = 0
  def initialize(pid : Int32)
    @info = Crystal::System::Process.new(pid)
  end
  def wc
    @wc
  end
end
module Crystal
module System
struct Process
  getter pid : LibC::PidT
  def initialize(@pid : LibC::PidT)
    @channel = SCH.wait(@pid)
  end
end
end
end
module SCH
  def self.wait(pid : LibC::PidT) : Chan(Int32)
    Chan(Int32).new(pid)
  end
end
o = Outer.new(5)
LibC.exit(o.wc == 0 ? 7 : 40)
CR

for name in module_before forward_struct module_after namespaced_generic_return inherited_class_method path_named_later_module path_named_namespaced_handler nested_module_later_module; do
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 300 8192 \
      "$WORK_DIR/$name.cr" --no-prelude -o "$WORK_DIR/$name" >"$WORK_DIR/$name.build.log" 2>&1; then
    echo "case $name: compile failed" >&2
    tail -20 "$WORK_DIR/$name.build.log" >&2
    exit 1
  fi
  "$ROOT_DIR/scripts/run_safe.sh" "$WORK_DIR/$name" 5 512 >"$WORK_DIR/$name.run.log" 2>&1 || true
  if ! grep -q '^\[EXIT: 7\]' "$WORK_DIR/$name.run.log"; then
    echo "case $name failed (want EXIT 7):" >&2
    grep -E '^\[EXIT' "$WORK_DIR/$name.run.log" >&2 || cat "$WORK_DIR/$name.run.log" >&2
    exit 1
  fi
done
echo struct_ivar_call_return_layout_repro_ok
