require "spec"
require "../src/compiler/frontend/ast"
require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"

include Adamas::Compiler

# Generated runtime blocks in alternatives belong to separate copies of the
# enclosing macro scan state. Neither alternatives nor nested controls may
# consume the enclosing macro's terminator or the following declaration.
[
  "{% if true %} begin {% else %} begin {% end %}",
  "{% if false %} begin {% else %} begin {% end %}",
  "{% if false %} begin {% elsif true %} begin {% else %} begin {% end %}",
  "{% for item in [1] %} {% if true %} begin {% else %} begin {% end %} {% end %}",
].each_with_index do |branches, index|
  it "keeps generated alternative block depth local (case #{index})" do
    source = <<-CRYSTAL
      macro define_value
        def value
          {% begin %}
            #{branches}
              37
            end
          {% end %}
        end
      end

      def sibling
        42
      end
      CRYSTAL
    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    program.roots.size.should eq(2)
    macro_def = program.arena[program.roots.first].as(Frontend::MacroDefNode)
    body = program.arena[macro_def.body].as(Frontend::MacroLiteralNode)
    body.pieces.select(&.kind.text?).map(&.text.to_s).join.should_not contain("def sibling")
    sibling = program.arena[program.roots.last].as(Frontend::DefNode)
    String.new(sibling.name).should eq("sibling")
  end
end
