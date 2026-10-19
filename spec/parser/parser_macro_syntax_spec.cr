require "spec"

require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/parser"

private def macro_runtime_interpolation_body(source : String) : {Adamas::Compiler::Frontend::AstArena, Adamas::Compiler::Frontend::MacroLiteralNode}
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program.roots.size.should eq(1)
  arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
  definition = arena[program.roots.first].as(Adamas::Compiler::Frontend::MacroDefNode)
  {arena, arena[definition.body].as(Adamas::Compiler::Frontend::MacroLiteralNode)}
end

private def macro_runtime_interpolation_expression_names(arena : Adamas::Compiler::Frontend::AstArena, pieces : Array(Adamas::Compiler::Frontend::MacroPiece)) : Array(String)
  pieces.compact_map do |piece|
    next unless piece.kind == Adamas::Compiler::Frontend::MacroPiece::Kind::Expression
    node = arena[piece.expr.not_nil!].as(Adamas::Compiler::Frontend::MacroExpressionNode)
    String.new(arena[node.expression].as(Adamas::Compiler::Frontend::IdentifierNode).name)
  end
end

private def macro_runtime_interpolation_text(pieces : Array(Adamas::Compiler::Frontend::MacroPiece)) : String
  pieces.compact_map(&.text).join
end

private def macro_runtime_interpolation_embedded_expression(name : String) : String
  "#" + "{{{" + name + "}}}"
end

private def macro_runtime_interpolation_runtime_expression(name : String) : String
  "#" + "{" + name + "}"
end

private def macro_runtime_interpolation_escaped_expression(name : String) : String
  "\\" + "{{" + name + "}}"
end

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Macro syntax (parser-level)" do
    it "parses macro expression interpolation" do
      source = "value = {{FOO}}"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::MacroExpression)
    end

    it "parses macro control block with nested expression as a macro if" do
      source = <<-CRYSTAL
      {% if flag %}
      value = 1
      {% else %}
      value = 2
      {% end %}
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      macro_if = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(macro_if).should eq(Adamas::Compiler::Frontend::NodeKind::MacroIf)

      macro_if_node = macro_if.as(Adamas::Compiler::Frontend::MacroIfNode)
      then_body = arena[macro_if_node.then_body]
      Adamas::Compiler::Frontend.node_kind(then_body).should eq(Adamas::Compiler::Frontend::NodeKind::MacroLiteral)
    end

    it "captures require statements inside macro control blocks" do
      source = <<-CRYSTAL
      {% if flag?(:unix) %}
        require "./unix/file_descriptor"
      {% end %}
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      macro_if = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(macro_if).should eq(Adamas::Compiler::Frontend::NodeKind::MacroIf)

      macro_if_node = macro_if.as(Adamas::Compiler::Frontend::MacroIfNode)
      macro_literal = arena[macro_if_node.then_body]
      Adamas::Compiler::Frontend.node_kind(macro_literal).should eq(Adamas::Compiler::Frontend::NodeKind::MacroLiteral)

      pieces = Adamas::Compiler::Frontend.node_macro_pieces(macro_literal).not_nil!
      text = pieces.compact_map(&.text).join
      text.should contain("require")
      text.should contain("./unix/file_descriptor")
    end

    it "parses keyword-named macros with bare splat and block params as a single macro def" do
      source = <<-CRYSTAL
      macro spawn(call, *, name = nil, same_thread = false, &block)
        {% if block %}
          {% raise "bad" %}
        {% end %}

        {% if call.is_a?(Call) %}
          {{call}}
        {% else %}
          spawn do
            {{call}}
          end
        {% end %}
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)

      arena = program.arena
      macro_def = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(macro_def).should eq(Adamas::Compiler::Frontend::NodeKind::MacroDef)

      macro_name = Adamas::Compiler::Frontend.node_macro_name(macro_def).not_nil!
      String.new(macro_name).should eq("spawn")
    end

    it "keeps class body members after a macro begin block with nested header controls" do
      source = <<-CRYSTAL
      class File
        {% begin %}
          def self.new(filename : String, mode = "r", {% if compare_versions(Crystal::VERSION, "1.5.0") >= 0 %} @[Deprecated] {% end %} blocking = nil)
            filename
          end
        {% end %}

        protected def self.new_internal(filename, mode = "r", blocking = nil)
          filename
        end

        getter path : String
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)

      arena = program.arena
      class_node = arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
      class_body = class_node.body.not_nil!

      class_body.size.should eq(3)

      macro_if = arena[class_body[0]]
      Adamas::Compiler::Frontend.node_kind(macro_if).should eq(Adamas::Compiler::Frontend::NodeKind::MacroIf)

      protected_def = arena[class_body[1]]
      Adamas::Compiler::Frontend.node_kind(protected_def).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      String.new(Adamas::Compiler::Frontend.node_def_name(protected_def).not_nil!).should eq("new_internal")
      Adamas::Compiler::Frontend.node_def_visibility(protected_def).should eq(Adamas::Compiler::Frontend::Visibility::Protected)
    end
  end
end

describe "macro string runtime interpolation boundary" do
  it "keeps a runtime interpolation opener beside an embedded macro argument" do
    source = "macro capture(arg)\n  \"prefix " + macro_runtime_interpolation_embedded_expression("arg") + " suffix\"\nend\n"
    arena, body = macro_runtime_interpolation_body(source)

    macro_runtime_interpolation_expression_names(arena, body.pieces).should eq(["arg"])
    text = macro_runtime_interpolation_text(body.pieces)
    text.should contain("prefix ")
    text.should contain("#" + "{")
    text.count('#').should eq(1)
  end

  it "extracts adjacent macro expressions without stealing either runtime opener" do
    source = "macro capture(left, right)\n  \"" +
             macro_runtime_interpolation_embedded_expression("left") +
             macro_runtime_interpolation_embedded_expression("right") +
             "\"\nend\n"
    arena, body = macro_runtime_interpolation_body(source)

    macro_runtime_interpolation_expression_names(arena, body.pieces).should eq(["left", "right"])
    macro_runtime_interpolation_text(body.pieces).count('#').should eq(2)
  end

  it "leaves ordinary runtime interpolation as macro text" do
    source = "macro capture(arg)\n  \"ordinary " +
             macro_runtime_interpolation_runtime_expression("arg") +
             " interpolation\"\nend\n"
    _, body = macro_runtime_interpolation_body(source)

    body.pieces.select { |piece| piece.kind == Adamas::Compiler::Frontend::MacroPiece::Kind::Expression }.should be_empty
    macro_runtime_interpolation_text(body.pieces).should contain(macro_runtime_interpolation_runtime_expression("arg"))
  end

  it "leaves escaped macro delimiters as text" do
    source = "macro capture(arg)\n  \"escaped " +
             macro_runtime_interpolation_escaped_expression("arg") +
             "\"\nend\n"
    _, body = macro_runtime_interpolation_body(source)

    body.pieces.select { |piece| piece.kind == Adamas::Compiler::Frontend::MacroPiece::Kind::Expression }.should be_empty
    macro_runtime_interpolation_text(body.pieces).should contain(macro_runtime_interpolation_escaped_expression("arg"))
  end
end
