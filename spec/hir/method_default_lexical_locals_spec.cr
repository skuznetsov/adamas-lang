require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_default_parameter_scope(
    owner : String,
    definition : Adamas::Compiler::Frontend::DefNode,
  ) : {Hash(String, TypeRef), Bool}
    caller_locals = {"pos" => TypeRef::POINTER, "caller_only" => TypeRef::STRING}
    caller_names = {"pos" => "Pointer(Int32)", "caller_only" => "String"}
    @current_typeof_locals = caller_locals
    @current_typeof_local_names = caller_names
    lower_method(owner, @class_info[owner], definition)
    function = @module.functions.find do |candidate|
      candidate.name.starts_with?("#{owner}#span") && !candidate.blocks.empty?
    end || raise "defaulted method was not materialized"
    types = {} of String => TypeRef
    function.params.each do |parameter|
      types[parameter.name] = parameter.type unless parameter.name == "self"
    end
    restored = @current_typeof_locals.try { |locals| locals.same?(caller_locals) } == true &&
               @current_typeof_local_names.try { |names| names.same?(caller_names) } == true
    {types, restored}
  end
end

private def default_parameter_scope_fixture(annotated : Bool)
  restriction = annotated ? " : Int32" : ""
  source = <<-CRYSTAL
    class DefaultParameterScopeOwner
      def span(pos#{restriction} = 0, length = pos)
        length
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  owner = arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
  definition = owner.body.not_nil!.compact_map do |id|
    arena[id].as?(Adamas::Compiler::Frontend::DefNode)
  end.first
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  converter.register_class(owner)
  {converter, definition}
end

describe "registered method default lexical locals" do
  [false, true].each do |annotated|
    it "binds the earlier #{annotated ? "annotated" : "defaulted"} formal before inferring a later default" do
      converter, definition = default_parameter_scope_fixture(annotated)
      types, restored = converter.__test_default_parameter_scope("DefaultParameterScopeOwner", definition)
      types.should eq({"pos" => Adamas::HIR::TypeRef::INT32, "length" => Adamas::HIR::TypeRef::INT32})
      restored.should be_true
    end
  end
end
