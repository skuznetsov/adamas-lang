# Regression: `->Module.method` (proc-pointer shorthand) must build a Proc value,
# NOT eagerly call the target method at the literal site.
#
# Bug: ast_to_hir.cr lower_unary lowered `node.operand` first, which for
# `->Foo.bar` invoked Foo.bar() at construction time and then emitted a Call
# of "->" on its result. Stage2 self-hosting hit this in
# Process.after_fork_child_callbacks where the body
#
#   ->Crystal::System::Signal.after_fork
#
# turned into a direct call to Signal.after_fork during array literal
# construction, derefing the @@pipe global before any pipe was set up.

# EXPECT: ok

module Foo
  def self.bar : Int32
    42
  end
end

p1 = ->Foo.bar
puts p1.is_a?(Proc) ? "ok-1" : "fail-1"
puts p1.call

# Two pointers to the same method should be independent Proc values.
p2 = ->Foo.bar
puts p1.call == p2.call ? "ok-2" : "fail-2"

puts "ok"
