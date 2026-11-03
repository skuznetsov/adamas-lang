require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  @@failed_materialization_armed = false
  @@failed_materialization_owner = ""
  @@failed_materialization_anchor = false
  @@failed_materialization_generation = nil.as(Function?)
  @@failed_materialization_failure_kind = "generic"
  @@failed_materialization_replacement = nil.as(Function?)

  private def lower_method_body_sequence_reentrant_safe(
    ctx : LoweringContext,
    body : Array(Adamas::Compiler::Frontend::ExprId),
    method_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : ValueId?
    if @@failed_materialization_armed && ctx.function.name.includes?("FailedPublicationOwner#value")
      @@failed_materialization_armed = false
      @@failed_materialization_owner = ctx.function.name
      @@failed_materialization_generation = ctx.function
      with_arena(method_arena) { lower_expr(ctx, body.first) }
      bits = {
        function_state(ctx.function.name).in_progress?,
        @function_defs[ctx.function.name]?.try do |definition|
          @function_def_arenas[ctx.function.name]?.try(&.same?(method_arena)) == true &&
            registered_arena_for_def(definition).try(&.same?(method_arena)) == true &&
            arena_fits_def?(method_arena, definition)
        end || false,
        @module.function_by_name(ctx.function.name).try(&.same?(ctx.function)) == true,
        @module.has_function_with_body?(ctx.function.name),
      }
      raise "invalid materialization anchor #{bits}" unless bits.all?
      @@failed_materialization_anchor = true
      case @@failed_materialization_failure_kind
      when "lowering"
        raise LoweringError.new("injected lowering failure")
      when "replace"
        old_generation = ctx.function
        raise "cannot retire old generation" unless remove_hir_function(old_generation.name)
        replacement = @module.create_function(old_generation.name, TypeRef::INT32)
        replacement_block = replacement.get_block(replacement.entry_block)
        replacement_value = Literal.new(replacement.next_value_id, TypeRef::INT32, 77_i64)
        replacement_block.add(replacement_value)
        replacement_block.terminator = Return.new(replacement_value.id)
        register_function_type(old_generation.name, TypeRef::INT32, allow_explicit_replacement: true)
        set_function_state(old_generation.name, FunctionLoweringState::Completed)
        @@failed_materialization_replacement = replacement
        raise "injected materialization failure"
      else
        raise "injected materialization failure"
      end
    end
    previous_def(ctx, body, method_arena)
  end

  def __test_failed_materialization(inject_failure : Bool) : {Bool, Bool, Bool, Bool, Bool, Bool}
    name = @function_defs.keys.find { |key| key.includes?("FailedPublicationOwner#value") } ||
      raise "missing parsed source target"
    @current_class = "PublicationOuterOwner"
    @@failed_materialization_owner = name
    @@failed_materialization_anchor = false
    @@failed_materialization_generation = nil
    @@failed_materialization_failure_kind = "generic"
    @@failed_materialization_armed = inject_failure
    injected = false
    begin
      lower_function_if_needed_profiled(name, __LINE__)
    rescue error
      raise error unless error.message == "injected materialization failure"
      injected = true
    ensure
      @@failed_materialization_armed = false
    end
    owner = @@failed_materialization_owner
    {
      injected,
      @@failed_materialization_anchor,
      @current_class == "PublicationOuterOwner",
      function_state(owner).completed?,
      @module.has_function_with_body?(owner),
      @module.function_by_name(owner).try do |function|
        function.return_type == TypeRef::INT32
      end || false,
    }
  end

  def __test_failed_materialization_adversary(failure_kind : String)
    owner = @function_defs.keys.find { |key| key.includes?("FailedPublicationOwner#value") } ||
      raise "missing parsed source target"
    sibling_name = @function_defs.keys.find { |key| key.includes?("FailedPublicationOwner#sibling") } ||
      raise "missing parsed sibling target"

    lower_function_if_needed_profiled(sibling_name, __LINE__)
    sibling = @module.function_by_name(sibling_name) || raise "missing materialized sibling"

    @current_class = "PublicationOuterOwner"
    @current_method = "caller"
    @current_method_is_class = true
    @current_typeof_locals = {"outer_local" => TypeRef::INT64}
    @current_typeof_local_names = {"outer_local" => "Int64"}
    @enum_value_types = {1_u32 => "OuterMethodUnwindEnum"}
    @closure_ref_cells = {} of String => {String, String, TypeRef}
    @closure_ref_cells["outer_capture"] = {"PublicationOuterOwner", "cell", TypeRef::INT32}
    @closure_ref_prefer_cell = Set(String).new << "outer_capture"

    @@failed_materialization_failure_kind = failure_kind
    @@failed_materialization_owner = owner
    @@failed_materialization_anchor = false
    @@failed_materialization_generation = nil
    @@failed_materialization_replacement = nil
    @@failed_materialization_armed = true
    raised_as_expected = false
    begin
      lower_function_if_needed_profiled(owner, __LINE__)
    rescue error
      raised_as_expected = case failure_kind
                           when "lowering"
                             error.is_a?(LoweringError) && error.message == "injected lowering failure"
                           when "replace"
                             error.message == "injected materialization failure"
                           else
                             false
                           end
    ensure
      @@failed_materialization_armed = false
    end

    old_generation = @@failed_materialization_generation
    live_owner = @module.function_by_name(owner)
    replacement = @@failed_materialization_replacement
    live_sibling = @module.function_by_name(sibling_name)
    {
      raised_as_expected: raised_as_expected,
      anchored_after_body_expr: @@failed_materialization_anchor,
      old_generation_retired: old_generation.nil? || live_owner.try(&.same?(old_generation)) != true,
      replacement_absent: replacement.nil? && live_owner.nil?,
      replacement_same_generation: replacement.try { |function| live_owner.try(&.same?(function)) } == true,
      replacement_body_retained: replacement.try { @module.has_function_with_body?(owner) } == true,
      replacement_completed_retained: replacement.try { function_state(owner).completed? } == true,
      sibling_same_generation: live_sibling.try(&.same?(sibling)) == true,
      sibling_body_retained: @module.has_function_with_body?(sibling_name),
      sibling_completed_retained: function_state(sibling_name).completed?,
      caller_scope_restored: @current_class == "PublicationOuterOwner" &&
                             @current_method == "caller" &&
                             @current_method_is_class &&
                             @current_typeof_locals == {"outer_local" => TypeRef::INT64} &&
                             @current_typeof_local_names == {"outer_local" => "Int64"} &&
                             @enum_value_types == {1_u32 => "OuterMethodUnwindEnum"} &&
                             @closure_ref_cells["outer_capture"]? == {"PublicationOuterOwner", "cell", TypeRef::INT32} &&
                             @closure_ref_prefer_cell.includes?("outer_capture"),
    }
  ensure
    @@failed_materialization_armed = false
  end
end

private def failed_materialization_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class FailedPublicationOwner
      def value : Int32
        65
      end

      def sibling : Int32
        66
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |root|
    converter.register_class(arena[root].as(Adamas::Compiler::Frontend::ClassNode))
  end
  converter
end

describe "failed source materialization publication" do
  it "retires its exact partial body and restores the outer class without publishing Completed" do
    injected, anchored, restored, completed, body, _ =
      failed_materialization_converter.__test_failed_materialization(true)
    injected.should be_true
    anchored.should be_true
    restored.should be_true
    completed.should be_false
    body.should be_false
  end

  it "still publishes a successfully completed typed source body" do
    injected, _, restored, completed, body, typed =
      failed_materialization_converter.__test_failed_materialization(false)
    injected.should be_false
    restored.should be_true
    completed.should be_true
    body.should be_true
    typed.should be_true
  end

  it "retires a partial generation after LoweringError and preserves a completed sibling" do
    state = failed_materialization_converter.__test_failed_materialization_adversary("lowering")
    state[:raised_as_expected].should be_true
    state[:anchored_after_body_expr].should be_true
    state[:old_generation_retired].should be_true
    state[:replacement_absent].should be_true
    state[:sibling_same_generation].should be_true
    state[:sibling_body_retained].should be_true
    state[:sibling_completed_retained].should be_true
    state[:caller_scope_restored].should be_true
  end

  it "does not let an old frame clear a same-name replacement after a generic exception" do
    state = failed_materialization_converter.__test_failed_materialization_adversary("replace")
    state[:raised_as_expected].should be_true
    state[:anchored_after_body_expr].should be_true
    state[:old_generation_retired].should be_true
    state[:replacement_absent].should be_false
    state[:replacement_same_generation].should be_true
    state[:replacement_body_retained].should be_true
    state[:replacement_completed_retained].should be_true
    state[:sibling_same_generation].should be_true
    state[:sibling_body_retained].should be_true
    state[:sibling_completed_retained].should be_true
    state[:caller_scope_restored].should be_true
  end
end

class Adamas::HIR::AstToHir
  def __test_normal_materialization_early_return
    owner = "PublicationClassOnlyMixin#value"
    raise "invalid class-only module anchor" unless @hierarchy.class_only_includers?("PublicationClassOnlyMixin")
    @current_class = "PublicationOuterOwner"
    lower_function_if_needed_profiled(owner, __LINE__)
    {@current_class == "PublicationOuterOwner", function_state(owner).in_progress?, @module.has_function_with_body?(owner)}
  end
end

private def early_return_materialization_converter
  source = <<-CRYSTAL
    enum PublicationEarlyReturnEnum
      Value
    end
    module PublicationClassOnlyMixin
      def value : Int32
        65
      end
    end
    class PublicationMixinOwner
      include PublicationClassOnlyMixin
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::EnumNode
      converter.register_enum(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter
end

describe "normal source materialization early return" do
  it "clears an unfinished module dispatch owner on a non-exceptional early return" do
    restored, in_progress, body = early_return_materialization_converter.__test_normal_materialization_early_return
    restored.should be_true
    body.should be_false
    in_progress.should be_false
  end
end
