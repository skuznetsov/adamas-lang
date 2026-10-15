require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_finish_accessor_visibility : Nil
    process_pending_lower_functions
    lower_missing_call_targets
  end
end

private def lower_accessor_visibility_fixture(source : String, lazy : Bool = false)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  classes = program.roots.compact_map { |id| arena[id].as?(Adamas::Compiler::Frontend::ClassNode) }
  classes.each { |node| converter.register_class(node) }
  classes.each { |node| converter.lower_class(node) } unless lazy
  expressions = program.roots.reject { |id| arena[id].is_a?(Adamas::Compiler::Frontend::ClassNode) }
  converter.lower_main(expressions.map(&.index.to_u64))
  converter.__test_finish_accessor_visibility if lazy
  converter
end

private def accessor_visibility_source(accessor : String, overload : String, call : String, reverse : Bool = false)
  members = reverse ? "#{overload}\n#{accessor}" : "#{accessor}\n#{overload}"
  <<-CRYSTAL
    class AccessorVisibilityProbe
      @state : Int32
      def initialize
        @state = 42
      end
      #{members}
    end
    #{call}
  CRYSTAL
end

describe "visibility of generated accessors beside source overloads" do
  {false, true}.each do |reverse|
    {false, true}.each do |lazy|
      it "retains the getter body beside a private overload (reverse=#{reverse}, lazy=#{lazy})" do
        converter = lower_accessor_visibility_fixture(accessor_visibility_source(
          "getter state", "private def state(value); @state = value; end",
          "AccessorVisibilityProbe.new.state", reverse,
        ), lazy)
        getter = converter.module.function_by_name("AccessorVisibilityProbe#state").not_nil!
        getter.params.size.should eq(1)
        instructions = getter.blocks.flat_map(&.instructions)
        instructions.select(Adamas::HIR::FieldGet).map(&.field_name).should eq(["@state"])
        instructions.select(Adamas::HIR::FieldSet).should be_empty
      end
    end
  end

  it "applies the same getter visibility to an explicit empty call" do
    lower_accessor_visibility_fixture(accessor_visibility_source(
      "getter state", "private def state(value); @state = value; end",
      "AccessorVisibilityProbe.new.state()",
    ))
  end

  it "keeps a private getter private beside a public one-argument overload" do
    expect_raises(Adamas::HIR::LoweringError, /private method 'state'/) do
      lower_accessor_visibility_fixture(accessor_visibility_source(
        "private getter state", "def state(value); @state = value; end",
        "AccessorVisibilityProbe.new.state",
      ))
    end
  end

  it "keeps the private one-argument overload private beside a public getter" do
    expect_raises(Adamas::HIR::LoweringError, /private method 'state'/) do
      lower_accessor_visibility_fixture(accessor_visibility_source(
        "getter state", "private def state(value); @state = value; end",
        "AccessorVisibilityProbe.new.state(43)",
      ))
    end
  end

  it "allows the public one-argument overload beside a private getter" do
    lower_accessor_visibility_fixture(accessor_visibility_source(
      "private getter state", "def state(value); @state = value; end",
      "AccessorVisibilityProbe.new.state(43)",
    ))
  end

  it "keeps an explicit private zero-argument redefinition private" do
    expect_raises(Adamas::HIR::LoweringError, /private method 'state'/) do
      lower_accessor_visibility_fixture(accessor_visibility_source(
        "getter state", "private def state; @state; end",
        "AccessorVisibilityProbe.new.state",
      ))
    end
  end

  it "keeps a private default-argument source overload private" do
    expect_raises(Adamas::HIR::LoweringError, /private method 'state'/) do
      lower_accessor_visibility_fixture(accessor_visibility_source(
        "getter state", "private def state(value = 41); @state = value; end",
        "AccessorVisibilityProbe.new.state",
      ), true)
    end
  end
end
