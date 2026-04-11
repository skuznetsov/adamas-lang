# Regression: macro directives embedded inside a string literal within
# {% begin %} ... {% end %} must be expanded. Mirrors the shape of
# Ryu's DIGIT_TABLE constant. V2 pre-lexes strings as single String
# tokens, so the parser needs to walk raw bytes and sub-parse embedded
# {% %} / {{ }} directives instead of treating the whole thing as
# opaque text.

module Outer::Inner
  {% begin %}
    TABLE = "{% for i in 0..3 %}x{{ i }}{% end %}"
  {% end %}
end

raise "bad single digit expansion" unless Outer::Inner::TABLE == "x0x1x2x3"

# Two-level nested for loops inside a string literal — shape
# identical to Ryu's DIGIT_TABLE.
module Ryu::Fake
  {% begin %}
    DIGITS = "{% for i in 0..2 %}{% for j in 0..1 %}{{ i }}{{ j }}{% end %}{% end %}"
  {% end %}
end

raise "bad nested expansion" unless Ryu::Fake::DIGITS == "000110112021"

# Plain interpolation (no control flow) inside a string literal.
module Plain::Interp
  {% begin %}
    NAME = "hello {{ 1 + 2 }} world"
  {% end %}
end

raise "bad interp expansion" unless Plain::Interp::NAME == "hello 3 world"

puts "module_begin_macro_string_literal_expansion_ok"
