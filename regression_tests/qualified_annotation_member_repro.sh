#!/usr/bin/env bash
# Qualified restrictions must resolve through includes and keep the concrete
# value ABI in the specialized method body.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/qualified-annotation-member.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

cat > "$WORK/included_frame.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

module Wire
  module Protocol
    abstract struct Frame
      abstract struct Method < Frame
      end
      abstract struct Basic < Method
        struct Cancel < Basic
        end
      end
    end
  end
end

module Server
  module AMQP
    include Wire::Protocol
    class Client
      def send(frame : AMQP::Frame, open : Bool? = nil) : Bool
        !!open && frame.is_a?(Wire::Protocol::Frame::Basic::Cancel)
      end
    end

    class Channel
      def initialize(@client : Client)
      end

      def send(frame)
        @client.send frame, true
      end
    end
  end
end

client = Server::AMQP::Client.new
channel = Server::AMQP::Channel.new(client)
ok = channel.send(Server::AMQP::Frame::Basic::Cancel.new)
LibC.putchar(ok ? 65 : 88)
LibC.putchar(10)
CRYSTAL

sed 's/frame : AMQP::Frame/frame : ::Server::AMQP::Frame/' \
  "$WORK/included_frame.cr" > "$WORK/rooted_include.cr"

sed 's/include Wire::Protocol/include ::Wire::Protocol/' \
  "$WORK/included_frame.cr" > "$WORK/rooted_include_target.cr"

# The relative include target binds under Server even with a root homonym.
awk '
  /^module Wire$/ { capture = 1 }
  /^module Server$/ {
    capture = 0
    print "module Wire; end"
    print
    printf "%s", nested
    next
  }
  capture { if (length($0)) nested = nested "  " $0 "\n"; next }
  { print }
' "$WORK/included_frame.cr" > "$WORK/scoped_include_target.cr"

# A root homonym cannot redirect a path whose head bound in the method owner.
{
  printf 'module AMQP\n  struct Frame\n  end\nend\n'
  cat "$WORK/included_frame.cr"
} > "$WORK/root_shadow.cr"

# Equivalent restrictions are one signature, so the last declaration wins.
write_redefinition() {
  local probe="$1" order="$2"
  awk -v order="$order" '
    function redefine() {
      print "      def send(frame : ::Wire::Protocol::Frame, open : Bool? = nil) : Bool"
      print "        false"
      print "      end"
    }
    /^      def send\(frame : AMQP::Frame/ && order == "first" { redefine() }
    /^      end$/ && append { print; redefine(); append = 0; next }
    /^      def send\(frame : AMQP::Frame/ && order == "last" { append = 1 }
    { print }
  ' "$WORK/included_frame.cr" > "$WORK/$probe.cr"
}
write_redefinition redefinition_last last
write_redefinition redefinition_first first
awk '/^    include Wire::Protocol/ { next }
     /^    class Channel/ { print "    include Wire::Protocol" }
     { print }' "$WORK/redefinition_last.cr" > "$WORK/late_include.cr"

# A direct member wins even when it is declared after the method.
sed -e '/^    class Channel/i\
    struct Frame\
    end
' -e 's/Wire::Protocol::Frame::Basic::Cancel)/Server::AMQP::Frame)/' \
  -e 's/Server::AMQP::Frame::Basic::Cancel.new/Server::AMQP::Frame.new/' \
  "$WORK/included_frame.cr" > "$WORK/late_direct_shadow.cr"

sed 's/channel.send(Server::AMQP::Frame::Basic::Cancel.new)/channel.send(7)/' \
  "$WORK/included_frame.cr" > "$WORK/wrong_frame.cr"
sed 's/@client.send frame, true/@client.send frame, 7/' \
  "$WORK/included_frame.cr" > "$WORK/wrong_open.cr"

# A missing member cannot restart the lookup under the root homonym.
{
  printf 'module AMQP\n  alias Other = Int32\nend\n'
  sed 's/frame : AMQP::Frame/frame : AMQP::Other/' "$WORK/wrong_frame.cr"
} > "$WORK/missing_lexical_member.cr"

cat > "$WORK/forward_alias_source.cr" <<'CRYSTAL'
abstract class Parent
end
class Child < Parent
end
class Parent
  alias Kind = UInt8 | Child::Kind
end
CRYSTAL

cat > "$WORK/forward_alias.cr" <<'CRYSTAL'
require "./forward_alias_source"

lib LibC
  fun putchar(value : Int32) : Int32
end

class Child
  alias Kind = Int32
end

def check
  {% raise "wrong alias members" unless Parent::Kind.union_types.size == 2 %}
  {% for type in Parent::Kind.union_types %}
    {% if type == Int32 %}
      LibC.putchar(65)
    {% end %}
  {% end %}
  LibC.putchar(10)
end
check
CRYSTAL

# A qualified alias declaration at file scope is the same direct member.
sed -e '/^class Child$/d' -e 's/^  alias Kind = Int32$/alias Child::Kind = Int32/' \
  -e '/^alias Child::Kind = Int32$/{n;d;}' "$WORK/forward_alias.cr" \
  > "$WORK/forward_qualified_alias.cr"

cat > "$WORK/inactive_shadow.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

class Parent
  alias Kind = Int32
end
class Child < Parent
  {% if false %}
    alias Kind = Bool
  {% end %}
end
def check(value : Child::Kind)
  LibC.putchar(value)
  LibC.putchar(10)
end
check(65)
CRYSTAL

cat > "$WORK/ordered_parent.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

class Base
  class Item
  end
end
class Mid < Base
end
class Leaf < Mid::Item
end
class Mid
  class Item
  end
end

def report(item : Base::Item)
  LibC.putchar(item.is_a?(Leaf) ? 65 : 88)
  LibC.putchar(10)
end
report(Leaf.new)
CRYSTAL

sed 's/class Leaf < Mid::Item/class Leaf < Mid::Future/; /class Mid$/{n;s/class Item/class Future/;}' \
  "$WORK/ordered_parent.cr" > "$WORK/forward_parent.cr"

# Ordinary signatures can bind through a later include. An explicit
# superclass can use the same edge only after the include was declared.
cat > "$WORK/parent_after_include.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
end

module Wire
  class Parent
  end
end
module Server
  module Protocol
    include Wire
    class Child < Protocol::Parent
    end
  end
end

LibC.putchar(Server::Protocol::Child.new.is_a?(Wire::Parent) ? 65 : 88)
LibC.putchar(10)
CRYSTAL

awk '/^    include Wire$/ { next }
     /^    class Child/ { move = 1 }
     /^    end$/ && move { print; print "    include Wire"; move = 0; next }
     { print }' "$WORK/parent_after_include.cr" > "$WORK/parent_before_include.cr"

run_positive() {
  local mode="$1" probe="$2" expected="$3"
  local output="$WORK/$mode.$probe"
  "${compile[@]}" "$WORK/$probe.cr" -o "$output" > "$output.compile.log" 2>&1 || {
    cat "$output.compile.log" >&2
    return 1
  }
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 \
    > "$output.stdout" 2> "$output.run.log" || {
      cat "$output.run.log" >&2
      return 1
    }
  printf '%s\n' "$expected" | diff -u - "$output.stdout"
  printf 'PASS: %s %s\n' "$mode" "$probe"
}

run_negative() {
  local mode="$1" probe="$2" diagnostic="$3"
  local output="$WORK/$mode.$probe"
  local rc=0
  "${compile[@]}" "$WORK/$probe.cr" -o "$output" > "$output.compile.log" 2>&1 || rc=$?
  if [[ "$rc" != 1 || -e "$output" ]] || ! rg -q "$diagnostic" "$output.compile.log"; then
    cat "$output.compile.log" >&2
    printf 'FAIL: %s %s expected source rejection, got exit %s\n' "$mode" "$probe" "$rc" >&2
    return 1
  fi
  printf 'PASS: %s %s rejects\n' "$mode" "$probe"
}

export CRYSTAL_CACHE_DIR="$WORK/cache"
for mode in stock lazy eager; do
  if [[ "$mode" == stock ]]; then
    compile=("$SAFE" "$ORIGINAL" 20 512 build --prelude=empty --single-module
      --no-debug --link-flags="$LINK_FLAGS")
    wrong_frame='expected argument #1.*Wire::Protocol::Frame.*Int32'
    wrong_open='expected argument #2.*Bool.*Int32'
    missing='undefined constant AMQP::Other'
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    compile=("${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$CANDIDATE" 20 512
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
    wrong_frame='no overload matches Server::AMQP::Client#send.*Int32, Bool'
    wrong_open='no overload matches Server::AMQP::Client#send.*Cancel, Int32'
    missing='(no overload matches Server::AMQP::Client#send|undefined constant .*AMQP::Other)'
  fi
  for probe in included_frame rooted_include rooted_include_target scoped_include_target \
      root_shadow late_direct_shadow redefinition_first forward_alias \
      forward_qualified_alias inactive_shadow ordered_parent parent_after_include; do
    run_positive "$mode" "$probe" A
  done
  run_positive "$mode" redefinition_last X
  run_positive "$mode" late_include X
  run_negative "$mode" wrong_frame "$wrong_frame"
  run_negative "$mode" wrong_open "$wrong_open"
  run_negative "$mode" missing_lexical_member "$missing"
  run_negative "$mode" forward_parent 'undefined constant Mid::Future'
  run_negative "$mode" parent_before_include 'undefined constant .*Protocol::Parent'
done
