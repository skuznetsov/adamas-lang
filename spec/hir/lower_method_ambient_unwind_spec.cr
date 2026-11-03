require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  @@test_lower_method_unwind_armed = false
  @@test_lower_method_unwind_observed_active_scope = false

  def self.__test_lower_method_unwind_arm : Nil
    @@test_lower_method_unwind_armed = true
    @@test_lower_method_unwind_observed_active_scope = false
  end

  def self.__test_lower_method_unwind_observed_active_scope? : Bool
    @@test_lower_method_unwind_observed_active_scope
  end

  private def lower_method_body_sequence_reentrant_safe(
    ctx : LoweringContext,
    body : Array(Adamas::Compiler::Frontend::ExprId),
    method_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : ValueId?
    if @@test_lower_method_unwind_armed
      @@test_lower_method_unwind_armed = false
      @@test_lower_method_unwind_observed_active_scope =
        @current_class == "MethodUnwindScopeOwner" &&
        @current_method == "explode" &&
        !@current_method_is_class &&
        @enum_value_types.nil? &&
        @closure_ref_cells.empty? &&
        @closure_ref_prefer_cell.empty? &&
        @current_typeof_locals.try(&.empty?) == true &&
        @current_typeof_local_names.try(&.empty?) == true
      raise "injected lower_method unwind"
    end

    previous_def(ctx, body, method_arena)
  end

  def __test_lower_method_with_outer_scope(
    class_name : String,
    node : Adamas::Compiler::Frontend::DefNode,
    inject_unwind : Bool,
  ) : {Bool, Bool, Bool}
    info = @class_info[class_name]? || raise "missing test class info #{class_name}"
    @current_class = "OuterMethodUnwindScope"
    @current_method = "caller"
    @current_method_is_class = true
    @current_typeof_locals = {"outer_local" => TypeRef::INT32}
    @current_typeof_local_names = {"outer_local" => "Int32"}
    @enum_value_types = {1_u32 => "OuterMethodUnwindEnum"}
    @closure_ref_cells = {} of String => {String, String, TypeRef}
    @closure_ref_cells["outer_capture"] = {"OuterMethodUnwindScope", "cell", TypeRef::INT32}
    @closure_ref_prefer_cell = Set(String).new << "outer_capture"

    expected = {
      @current_class,
      @current_method,
      @current_method_is_class,
      @current_typeof_locals.try(&.dup),
      @current_typeof_local_names.try(&.dup),
      @enum_value_types.try(&.dup),
      @closure_ref_cells.dup,
      @closure_ref_prefer_cell.dup,
    }

    if inject_unwind
      Adamas::HIR::AstToHir.__test_lower_method_unwind_arm
    end
    raised = false
    begin
      lower_method(class_name, info, node)
    rescue ex
      raised = ex.message == "injected lower_method unwind"
    ensure
      @@test_lower_method_unwind_armed = false
    end

    restored = {
      @current_class,
      @current_method,
      @current_method_is_class,
      @current_typeof_locals.try(&.dup),
      @current_typeof_local_names.try(&.dup),
      @enum_value_types.try(&.dup),
      @closure_ref_cells.dup,
      @closure_ref_prefer_cell.dup,
    } == expected
    {raised, Adamas::HIR::AstToHir.__test_lower_method_unwind_observed_active_scope?, restored}
  end
end

private def lower_method_unwind_fixture : Tuple(Adamas::HIR::AstToHir, String, Adamas::Compiler::Frontend::DefNode)
  source = <<-CRYSTAL
    class MethodUnwindScopeOwner
      def explode : Int32
        65
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  class_node = program.roots.compact_map do |root_id|
    arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
  end.first || raise "missing test class"
  class_name = String.new(class_node.name)
  method_node = class_node.body.not_nil!.compact_map do |member_id|
    arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
  end.first || raise "missing test method"

  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.register_class(class_node)
  {converter, class_name, method_node}
end

describe "lower_method ambient scope unwind" do
  it "restores the caller ambient scope after a non-lowering exception in the body" do
    converter, class_name, method_node = lower_method_unwind_fixture
    raised, observed_active_scope, restored = converter.__test_lower_method_with_outer_scope(
      class_name, method_node, true,
    )
    raised.should be_true
    observed_active_scope.should be_true
    restored.should be_true
  end

  it "keeps the normal successful body path and restores the caller scope" do
    converter, class_name, method_node = lower_method_unwind_fixture
    raised, _, restored = converter.__test_lower_method_with_outer_scope(
      class_name, method_node, false,
    )
    raised.should be_false
    restored.should be_true
  end
end
