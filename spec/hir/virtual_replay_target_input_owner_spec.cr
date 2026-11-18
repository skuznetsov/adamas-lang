require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_df_materialize_nilary(method : String) : String
    base = "ReplayInputOwner##{method}"
    remember_callsite_arg_types(base, ([] of TypeRef), ([] of Bool))
    lower_function_if_needed(base)
    function = @module.function_by_name(base).not_nil!
    @module.has_function_with_body?(base).should be_true
    function.return_type.should eq(TypeRef::INT32)
    # The exact nilary input can be retained again after a prior consumer took
    # it. A family sibling must not reinterpret this physical body recipe.
    remember_callsite_arg_types(base, ([] of TypeRef), ([] of Bool))
    base
  end

  def __test_df_lookup(
    owner : String,
    method : String,
    types : Array(TypeRef),
    has_block : Bool = false,
  ) : String?
    lookup_function_def_for_call("#{owner}##{method}", types.size, has_block, types, false).try(&.[0])
  end

  def __test_df_defer_replay(
    route : Symbol,
    method : String,
    types : Array(TypeRef),
    has_block : Bool = false,
  ) : Bool
    saved_depth = @lowering_depth
    complete = false
    begin
      @lowering_depth = @lowering_depth_limit + 1
      case route
      when :resolved
        complete = lower_virtual_target_resolved("ReplayInputOwner", method, types, has_block, false)
      when :owner
        lower_virtual_target_owner("ReplayInputOwner", method, types, has_block, false)
      when :final
        lower_final_repair_virtual_target_owner("ReplayInputOwner", method, types, has_block, false)
      else
        raise "unknown replay test route #{route}"
      end
    ensure
      @lowering_depth = saved_depth
    end
    complete
  end

  def __test_df_demanded?(name : String) : Bool
    @virtual_target_body_demands.includes?(name)
  end

  def __test_df_exact_inputs(name : String)
    if inputs = @pending_arg_types[name]?
      {inputs.types.dup, inputs.literals.try(&.dup), inputs.has_block}
    end
  end

  def __test_union_replay_argument_kinds(kinds : Array(Bool?)) : Nil
    owners = ["ReplayInputOwner", "ReplaySecondOwner"]
    union = @module.intern_type(TypeDescriptor.new(TypeKind::Union, owners.join(" | "), owners.map { |owner| type_ref_for_name(owner) }))
    caller = @module.create_function("union_input_kinds", TypeRef::VOID)
    receiver = caller.add_param("receiver", union)
    ctx = LoweringContext.new(caller, @module, @arena)
    ctx.register_type(receiver.id, union)
    types = [TypeRef::BOOL]

    saved_depth = @lowering_depth
    begin
      @lowering_depth = @lowering_depth_limit + 1
      kinds.each do |kind|
        facts = kind.nil? ? nil : [SourceCallArgument.new(TypeRef::BOOL, kind)] of SourceCallArgument?
        ensure_virtual_call_targets_lowered(ctx, receiver.id, "echo", types, false, false, false, false,
          source_argument_facts: facts)
      end
    ensure
      @lowering_depth = saved_depth
    end

    owners.each do |owner|
      kinds.each do |kind|
        facts = kind.nil? ? nil : [SourceCallArgument.new(TypeRef::BOOL, kind)] of SourceCallArgument?
        target = virtual_target_mangled_name("#{owner}#echo", types, false, facts)
        inputs = @pending_arg_types[target]?.not_nil!
        inputs.types.should eq(types)
        inputs.literals.should eq(kind.nil? ? nil : [kind])
        inputs.source_argument_facts.should eq(facts)
      end
    end
  end

  def __test_df_materialize_inherited_specialization : Tuple(String, String)
    owner = "ReplaySpecializedChild"
    base = "#{owner}#work"
    types = [TypeRef::INT32]
    resolved = lookup_function_def_for_call(base, 1, false, types, false).not_nil!
    declaration_name = resolved[0]
    definition = resolved[1]
    source_arena = registered_arena_for_def(definition).not_nil!
    exact_name = virtual_replay_specialized_name(declaration_name, types, false)
    exact_name.should_not eq(declaration_name)
    method_owner(strip_type_suffix(exact_name)).should eq("ReplaySpecializedParent")

    # Enter the actual final-repair producer while another body is lowering.
    # It must queue the concrete ancestor target selected from this Def.
    saved_depth = @lowering_depth
    begin
      @lowering_depth = @lowering_depth_limit + 1
      lower_final_repair_virtual_target_owner(owner, "work", types, false, false)
    ensure
      @lowering_depth = saved_depth
    end
    @virtual_target_body_demands.includes?(exact_name).should be_true
    function_state(exact_name).pending?.should be_true
    @module.has_function_with_body?(exact_name).should be_false

    # Drain only that queued exact target, without running later signature
    # emission that could hide a readiness miss by creating the declaration.
    lower_function_if_needed(exact_name)
    function = @module.function_by_name(exact_name).not_nil!
    @module.has_function_with_body?(exact_name).should be_true
    function.return_type.should eq(TypeRef::INT32)
    function.params.last.type.should eq(TypeRef::INT32)
    @function_defs[declaration_name].same?(definition).should be_true
    @function_def_arenas[declaration_name].object_id.should eq(source_arena.object_id)
    @module.has_function_with_body?(declaration_name).should be_false
    @module.has_function_with_body?(strip_type_suffix(declaration_name)).should be_false
    @module.has_function_with_body?(mangle_function_name(base, types, false)).should be_false
    {declaration_name, exact_name}
  end

  def __test_df_inherited_body_available?(argument_type : TypeRef = TypeRef::INT32) : Bool
    owner = "ReplaySpecializedChild"
    base = "#{owner}#work"
    types = [argument_type]
    candidate = mangle_function_name(base, types, false)
    repair_resolved_body_available?(owner, base, candidate, types, false, false)
  end

  def __test_df_repeat_inherited_final_repair : Int32
    execute_final_repair_virtual_target_requests([
      {"ReplaySpecializedChild", "ReplaySpecializedParent", "work", [TypeRef::INT32], false, false, nil},
    ] of {String, String, String, Array(TypeRef), Bool, Bool, Array(SourceCallArgument?)?})
  end
end

private def virtual_replay_target_input_fixture : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class ReplayInputOwner
      def step : Int32
        65
      end

      def step(value : Bool) : Int32
        66
      end

      def alone : Int32
        67
      end

      def echo(value)
        value
      end
    end

    class ReplaySecondOwner
      def echo(value)
        value
      end
    end

    class ReplaySpecializedParent
      def work(value : T) : T forall T
        value
      end
    end

    class ReplaySpecializedChild < ReplaySpecializedParent
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.ast_arena, sources_by_arena: {parsed.ast_arena.object_id.to_u64 => source})
  converter.no_prelude = true
  parsed.roots.each do |id|
    converter.register_class(parsed.ast_arena[id].as(Adamas::Compiler::Frontend::ClassNode))
  end
  converter
end

describe "virtual replay target input ownership" do
  it "retains value and class-object demands on each union receiver in either discovery order" do
    virtual_replay_target_input_fixture.__test_union_replay_argument_kinds([false, true] of Bool?)
    virtual_replay_target_input_fixture.__test_union_replay_argument_kinds([true, false] of Bool?)
  end

  it "keeps an unobserved kind unknown on each union receiver" do
    virtual_replay_target_input_fixture.__test_union_replay_argument_kinds([nil] of Bool?)
  end

  it "does not demand an unrelated nilary body after a typed resolved lookup fails" do
    converter = virtual_replay_target_input_fixture
    base = converter.__test_df_materialize_nilary("step")
    before = converter.__test_df_exact_inputs(base).not_nil!
    types = [Adamas::HIR::TypeRef::INT32]
    converter.__test_df_lookup("ReplayInputOwner", "step", types).should be_nil

    converter.__test_df_defer_replay(:resolved, "step", types).should be_false

    converter.__test_df_demanded?("#{base}$Int32").should be_true
    converter.__test_df_exact_inputs(base).should eq(before)
    converter.__test_df_demanded?(base).should be_false
  end

  it "does not demand the no-block body after a resolved block lookup fails" do
    converter = virtual_replay_target_input_fixture
    base = converter.__test_df_materialize_nilary("alone")
    before = converter.__test_df_exact_inputs(base).not_nil!
    types = [] of Adamas::HIR::TypeRef
    converter.__test_df_lookup("ReplayInputOwner", "alone", types, true).should be_nil

    converter.__test_df_defer_replay(:resolved, "alone", types, true).should be_false

    converter.__test_df_demanded?("#{base}$block").should be_true
    converter.__test_df_exact_inputs(base).should eq(before)
    converter.__test_df_demanded?(base).should be_false
  end

  [:owner, :final].each do |route|
    it "keeps the existing #{route} failed-lookup route on the typed candidate" do
      converter = virtual_replay_target_input_fixture
      base = converter.__test_df_materialize_nilary("step")
      types = [Adamas::HIR::TypeRef::INT32]
      converter.__test_df_lookup("ReplayInputOwner", "step", types).should be_nil

      converter.__test_df_defer_replay(route, "step", types)

      converter.__test_df_demanded?("#{base}$Int32").should be_true
      converter.__test_df_demanded?(base).should be_false
    end
  end

  it "still demands a bare target when the nilary no-block source call selects it" do
    converter = virtual_replay_target_input_fixture
    base = converter.__test_df_materialize_nilary("alone")
    types = [] of Adamas::HIR::TypeRef
    converter.__test_df_lookup("ReplayInputOwner", "alone", types).should eq(base)

    converter.__test_df_defer_replay(:resolved, "alone", types).should be_true

    converter.__test_df_demanded?(base).should be_true
  end

  it "recognizes the selected concrete forall ancestor body after queued replay settles" do
    converter = virtual_replay_target_input_fixture
    converter.__test_df_materialize_inherited_specialization

    converter.__test_df_inherited_body_available?.should be_true
  end

  it "does not execute final repair again for the same settled specialization" do
    converter = virtual_replay_target_input_fixture
    converter.__test_df_materialize_inherited_specialization

    converter.__test_df_repeat_inherited_final_repair.should eq(0)
  end

  it "does not treat an Int32 specialization as readiness for an Int64 request" do
    converter = virtual_replay_target_input_fixture
    converter.__test_df_materialize_inherited_specialization

    converter.__test_df_inherited_body_available?(Adamas::HIR::TypeRef::INT64).should be_false
  end
end
