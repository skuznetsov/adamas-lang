require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 74: Proc literal (->) (PRODUCTION-READY)" do
    it "parses parameterless proc with brace form" do
      source = "-> { 42 }"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      proc_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(proc_node).should eq(Adamas::Compiler::Frontend::NodeKind::ProcLiteral)

      params = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).params
      params.should_not be_nil
      params.not_nil!.size.should eq(0)

      body = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).body.not_nil!
      body.size.should eq(1)

      body_expr = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(body_expr).should eq(Adamas::Compiler::Frontend::NodeKind::Number)
    end

    it "parses single parameter without type annotation" do
      source = "->(x) { x + 1 }"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      proc_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(proc_node).should eq(Adamas::Compiler::Frontend::NodeKind::ProcLiteral)

      params = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).params.not_nil!
      params.size.should eq(1)
      String.new(params[0].name.not_nil!).should eq("x")
      params[0].type_annotation.should be_nil
    end

    it "parses single parameter with type annotation" do
      source = "->(x : Int32) { x + 1 }"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      proc_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(proc_node).should eq(Adamas::Compiler::Frontend::NodeKind::ProcLiteral)

      params = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).params.not_nil!
      params.size.should eq(1)
      String.new(params[0].name.not_nil!).should eq("x")

      type_annotation = params[0].type_annotation.not_nil!
      String.new(type_annotation).should eq("Int32")
    end

    it "parses two parameters with type annotations" do
      source = "->(x : Int32, y : Int32) { x + y }"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      proc_node = arena[program.roots[0]]
      params = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).params.not_nil!
      params.size.should eq(2)

      String.new(params[0].name.not_nil!).should eq("x")
      String.new(params[0].type_annotation.not_nil!).should eq("Int32")

      String.new(params[1].name.not_nil!).should eq("y")
      String.new(params[1].type_annotation.not_nil!).should eq("Int32")
    end

    it "parses two parameters without type annotations" do
      source = "->(x, y) { x + y }"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      proc_node = arena[program.roots[0]]
      params = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).params.not_nil!
      params.size.should eq(2)

      String.new(params[0].name.not_nil!).should eq("x")
      params[0].type_annotation.should be_nil

      String.new(params[1].name.not_nil!).should eq("y")
      params[1].type_annotation.should be_nil
    end

    it "parses proc with return type annotation" do
      source = "->(x : Int32) : Int32 { x * 2 }"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      proc_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(proc_node).should eq(Adamas::Compiler::Frontend::NodeKind::ProcLiteral)

      return_type = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).return_type.not_nil!
      String.new(return_type).should eq("Int32")
    end

    it "parses proc with do...end form" do
      source = <<-CRYSTAL
      ->(x : Int32) do
        x + 1
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      proc_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(proc_node).should eq(Adamas::Compiler::Frontend::NodeKind::ProcLiteral)

      params = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).params.not_nil!
      params.size.should eq(1)
      String.new(params[0].name.not_nil!).should eq("x")

      body = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).body.not_nil!
      body.size.should eq(1)
    end

    it "parses proc with multi-statement body" do
      source = <<-CRYSTAL
      ->(x : Int32) {
        y = x + 1
        y * 2
      }
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      proc_node = arena[program.roots[0]]
      body = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).body.not_nil!
      body.size.should eq(2)
    end

    it "parses nested proc literals" do
      source = "-> { ->(x) { x } }"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      outer_proc = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(outer_proc).should eq(Adamas::Compiler::Frontend::NodeKind::ProcLiteral)

      outer_body = outer_proc.as(Adamas::Compiler::Frontend::ProcLiteralNode).body.not_nil!
      outer_body.size.should eq(1)

      inner_proc = arena[outer_body[0]]
      Adamas::Compiler::Frontend.node_kind(inner_proc).should eq(Adamas::Compiler::Frontend::NodeKind::ProcLiteral)
    end

    it "parses proc as method call argument" do
      source = "foo(->(x) { x })"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(call).should eq(Adamas::Compiler::Frontend::NodeKind::Call)

      args = Adamas::Compiler::Frontend.node_args(call).not_nil!
      args.size.should eq(1)

      proc_arg = arena[args[0]]
      Adamas::Compiler::Frontend.node_kind(proc_arg).should eq(Adamas::Compiler::Frontend::NodeKind::ProcLiteral)
    end

    it "parses typed array of proc type with no return" do
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new("arr = [] of ->")
      )
      parser.parse_program
      parser.diagnostics.size.should eq(0)
    end

    it "parses typed array of proc type with single arg and no return" do
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new("hooks = [] of Example::Procsy ->")
      )
      parser.parse_program
      parser.diagnostics.size.should eq(0)
    end

    it "keeps typed proc arrays inside method bodies as assignments" do
      source = <<-CRYSTAL
      module Crystal::AtExitHandlers
        def self.add(handler)
          handlers = [] of Int32, ::Exception? ->
          handlers << handler
        end
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)

      arena = program.arena
      root = arena[program.roots[0]]
      outer_body = Adamas::Compiler::Frontend.node_module_body(root).not_nil!
      inner_module = arena[outer_body[0]]
      inner_body = Adamas::Compiler::Frontend.node_module_body(inner_module).not_nil!
      def_node = arena[inner_body[0]]
      def_body = Adamas::Compiler::Frontend.node_def_body(def_node).not_nil!

      def_body.size.should eq(2)

      assign = arena[def_body[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::ArrayLiteral)

      of_type = arena[Adamas::Compiler::Frontend.node_array_of_type(value).not_nil!]
      Adamas::Compiler::Frontend.node_kind(of_type).should eq(Adamas::Compiler::Frontend::NodeKind::Identifier)
    end

    it "parses proc assigned to variable" do
      source = "p = ->(x) { x }"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      value = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(value).should eq(Adamas::Compiler::Frontend::NodeKind::ProcLiteral)
    end

    it "parses multiline typed proc params in do/end form inside method bodies" do
      source = <<-CRYSTAL
      def foo
        worker = ->(
          owner : String,
          count : Int32
        ) do
          count
        end
        worker
      end

      def bar
        1
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      # The proc literal end must not terminate the surrounding def body.
      # Both defs should remain top-level roots.
      program.roots.size.should eq(2)
      arena = program.arena

      foo = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(foo).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      String.new(foo.as(Adamas::Compiler::Frontend::DefNode).name).should eq("foo")

      bar = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_kind(bar).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      String.new(bar.as(Adamas::Compiler::Frontend::DefNode).name).should eq("bar")
    end

    it "parses proc with empty body" do
      source = "-> { }"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      proc_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(proc_node).should eq(Adamas::Compiler::Frontend::NodeKind::ProcLiteral)

      body = proc_node.as(Adamas::Compiler::Frontend::ProcLiteralNode).body.not_nil!
      body.size.should eq(0)
    end
  end
end
