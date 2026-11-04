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

  it "keeps a chain of postfix conditions inside an assigned block" do
    source = <<-CRYSTAL
      class Demo
        def first
          result = collect do |item|
            next unless accepts?(item) if enabled?
            item
          rescue ex
            next
          end
          result
        end

        class Nested < Base; end
      end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    parser.diagnostics.should be_empty
    arena = program.arena
    class_body = arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode).body.not_nil!
    class_body.size.should eq(2)
    definition = arena[class_body[0]].as(Adamas::Compiler::Frontend::DefNode)
    nested = arena[class_body[1]].as(Adamas::Compiler::Frontend::ClassNode)
    String.new(nested.name).should eq("Nested")

    method_body = definition.body.not_nil!
    method_body.size.should eq(2)
    assignment = arena[method_body[0]].as(Adamas::Compiler::Frontend::AssignNode)
    call = arena[assignment.value].as(Adamas::Compiler::Frontend::CallNode)
    block = arena[call.block.not_nil!].as(Adamas::Compiler::Frontend::BlockNode)
    handler = arena[block.body.first].as(Adamas::Compiler::Frontend::BeginNode)
    outer = arena[handler.body.first].as(Adamas::Compiler::Frontend::IfNode)
    inner = arena[outer.then_body.first].as(Adamas::Compiler::Frontend::UnlessNode)
    arena[inner.then_branch.first].should be_a(Adamas::Compiler::Frontend::NextNode)
    outer.span.end_line.should eq(4)
  end

  it "keeps a parenthesized postfix expression inside a condition" do
    source = "result = 7 if (ready? if enabled?) unless stopped?"
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    parser.diagnostics.should be_empty
    program.roots.size.should eq(1)
    arena = program.arena
    outer = arena[program.roots.first].as(Adamas::Compiler::Frontend::UnlessNode)
    inner = arena[outer.then_branch.first].as(Adamas::Compiler::Frontend::IfNode)
    group = arena[inner.condition].as(Adamas::Compiler::Frontend::GroupingNode)
    arena[group.expression].should be_a(Adamas::Compiler::Frontend::IfNode)
    arena[inner.then_body.first].should be_a(Adamas::Compiler::Frontend::AssignNode)
  end

  it "leaves suffixes outside a logical RHS unless explicitly grouped" do
    ["return 1", "break 1", "next 1", "yield", "super", "previous_def"].each do |rhs|
      source = "check || #{rhs} if enabled\ncheck || (#{rhs} if enabled)"
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(2)
      arena = program.arena
      outer = arena[program.roots[0]].as(Adamas::Compiler::Frontend::IfNode)
      arena[outer.then_body.first].should be_a(Adamas::Compiler::Frontend::BinaryNode)
      binary = arena[program.roots[1]].as(Adamas::Compiler::Frontend::BinaryNode)
      group = arena[binary.right].as(Adamas::Compiler::Frontend::GroupingNode)
      arena[group.expression].should be_a(Adamas::Compiler::Frontend::IfNode)
    end
  end
end
