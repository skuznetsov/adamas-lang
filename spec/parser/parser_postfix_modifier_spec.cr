require "spec"

require "../../src/compiler/bootstrap_shims"
require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser postfix modifiers" do
  it "does not attach a following if to a multiline if-assignment" do
    source = <<-CRYSTAL
      def f(x = true) : Nil
        ret =
          if x
            1
          else
            2
          end

        if ret != 0
          4
        end
      end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    parser.diagnostics.should be_empty
    program.roots.size.should eq(1)

    arena = program.arena
    method_def = arena[program.roots.first].as(Adamas::Compiler::Frontend::DefNode)
    body = method_def.body.not_nil!

    body.size.should eq(2)
    arena[body[0]].should be_a(Adamas::Compiler::Frontend::AssignNode)
    arena[body[1]].should be_a(Adamas::Compiler::Frontend::IfNode)
  end

  it "keeps subsequent defs inside the surrounding module" do
    source = <<-CRYSTAL
      module Demo
        def first(x = true) : Nil
          ret =
            if x
              1
            else
              2
            end

          if ret != 0
            4
          end
        end

        def second
          5
        end
      end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    parser.diagnostics.should be_empty
    program.roots.size.should eq(1)

    arena = program.arena
    module_node = arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
    body = module_node.body.not_nil!

    body.size.should eq(2)
    arena[body[0]].should be_a(Adamas::Compiler::Frontend::DefNode)
    arena[body[1]].should be_a(Adamas::Compiler::Frontend::DefNode)
    String.new(arena[body[0]].as(Adamas::Compiler::Frontend::DefNode).name).should eq("first")
    String.new(arena[body[1]].as(Adamas::Compiler::Frontend::DefNode).name).should eq("second")
  end

  it "keeps a postfix unless attached to a multiline parenthesized call" do
    source = <<-CRYSTAL
      class Demo
        def first(init_name, callsite_init_types, call_has_block)
          remember_callsite_arg_types(
            init_name,
            callsite_init_types,
            nil,
            nil,
            call_has_block,
          ) unless callsite_init_types.empty?
          finish
        end

        def second
          2
        end
      end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    parser.diagnostics.should be_empty
    program.roots.size.should eq(1)

    arena = program.arena
    class_node = arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
    body = class_node.body.not_nil!

    body.size.should eq(2)
    first = arena[body[0]].as(Adamas::Compiler::Frontend::DefNode)
    second = arena[body[1]].as(Adamas::Compiler::Frontend::DefNode)
    String.new(first.name).should eq("first")
    String.new(second.name).should eq("second")

    first_body = first.body.not_nil!
    first_body.size.should eq(2)
    arena[first_body[0]].should be_a(Adamas::Compiler::Frontend::UnlessNode)
    arena[first_body[1]].should be_a(Adamas::Compiler::Frontend::IdentifierNode)

    unless_node = arena[first_body[0]].as(Adamas::Compiler::Frontend::UnlessNode)
    call = arena[unless_node.then_branch.first].as(Adamas::Compiler::Frontend::CallNode)
    closing_line = source.lines.index { |line| line.strip.starts_with?(") unless") }.not_nil! + 1
    call.span.end_line.should eq(closing_line)
    unless_node.span.end_line.should eq(closing_line)
  end
end
