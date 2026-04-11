# Regression: a `{% begin %} ... {% end %}` macro block inside a module that
# is declared with a multi-segment path (e.g. `module A::B::C`) must register
# constants at `A::B::C::Name`, NOT at a doubled path like
# `A::B::C::B::C::Name`.
#
# Root cause (fixed): wrap_module_body_macro_output used to re-emit the full
# owner path as the wrapper module (`module A::B::C ... end`). The reparser
# splits multi-segment module declarations into nested ModuleNodes, so the
# outer wrapper's body became `ModuleNode("B")` > `ModuleNode("C")` > members.
# process_begin_macro_if_in_module then prepended the original owner path to
# the nested module names, producing `A::B::C::B::C` for registration.
#
# As a consequence, `DIGIT_TABLE` declared inside a begin-macro in
# `Float::Printer::RyuPrintf` was registered under
# `Float::Printer::RyuPrintf::Printer::RyuPrintf::DIGIT_TABLE`, lookups from
# inside `append_n_digits` missed, and `DIGIT_TABLE + c` fell through to a
# generic union binary op that bottomed out in `STUB CALLED:
# UInt32#copy_to$Pointer(UInt8)_Int32`.
#
# Fix: wrap with a sentinel `module __V2MacroBody__` (mirroring the class-body
# variant), so the reparsed wrapper always has a single level and the body is
# iterated directly at the real owner path.
#
# EXPECT: module_begin_macro_nested_path_ok

module Outer::Middle::Inner
  {% begin %}
    BEGIN_CONST = {% for i in 1..3 %}{{ i }} &+ {% end %}0
  {% end %}
end

raise "BEGIN_CONST wrong" unless Outer::Middle::Inner::BEGIN_CONST == 6

# Also ensure the bare name resolves from inside the module.
module Outer::Middle::Inner
  def self.sum : Int32
    BEGIN_CONST
  end
end

raise "bare lookup wrong" unless Outer::Middle::Inner.sum == 6

puts "module_begin_macro_nested_path_ok"
