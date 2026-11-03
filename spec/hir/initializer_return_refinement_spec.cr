require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_initializer_return_source_functions : Array(Adamas::HIR::Function)
    @materialized_initializer_sources.values.map(&.function)
  end

  def __test_natural_initializer_source_name : String
    @materialized_initializer_sources.each do |name, source|
      if source.owner == "NaturalInitializerReplayOwner" &&
         source.source_name == "NaturalInitializerReplayOwner#initialize$block"
        return name
      end
    end
    raise "natural initializer replay fixture did not materialize its source recipe"
  end

  def __test_natural_initializer_state(name : String)
    source = @materialized_initializer_sources[name]
    current_function = @module.function_by_name(name)
    callback_type = @class_info["NaturalInitializerReplayOwner"].ivars.find do |ivar|
      ivar.name == "@callback"
    end.try(&.type)
    allocator_calls = [] of {String, Adamas::HIR::TypeRef}
    @module.functions.each do |function|
      next unless function.name.starts_with?("NaturalInitializerReplayOwner.new")
      function.blocks.each do |block|
        block.instructions.each do |instruction|
          next unless call = instruction.as?(Adamas::HIR::Call)
          next unless call.method_name == name
          allocator_calls << {call.method_name, call.type}
        end
      end
    end

    {
      source_name: source.source_name,
      source_def_identity: source.source_def.object_id,
      source_arena_identity: source.source_arena.object_id,
      function_identity: source.function.object_id,
      function_return: source.function.return_type,
      cached_return: source.return_type,
      return_invalidated: source.return_result_invalidated,
      parameter_types: source.parameter_types.dup,
      block_parameters: source.block_parameters.dup,
      heap_block_param: source.heap_block_param,
      live_function_identity: current_function.try(&.object_id),
      live_function_has_body: @module.has_function_with_body?(name),
      state_completed: function_state(name).completed?,
      registry_return: @function_types[name]?,
      callback_type: callback_type,
      allocator_calls: allocator_calls,
    }
  end

  def __test_initializer_return_update_admitted?(
    name : String,
    prior_return : Adamas::HIR::TypeRef,
    current_return : Adamas::HIR::TypeRef,
    new_generation : Bool,
    mismatch : Symbol? = nil,
    tracked_invalidation : Bool = true,
  ) : Bool
    source = @materialized_initializer_sources[name]
    function = source.function
    function.return_type = prior_return
    register_function_type(name, prior_return, allow_explicit_replacement: true)
    prior = initializer_return_refinement_spec_source(source, function, prior_return)
    @materialized_initializer_sources[name] = prior

    replay_source = nil.as(MaterializedInitializerSource?)
    current_function = if new_generation
                         removed = if tracked_invalidation
                                     remove_hir_function(name)
                                   else
                                     @module.remove_function(name)
                                   end
                         raise "expected previous initializer generation to be installed" unless removed
                         replay_source = @materialized_initializer_sources[name]?
                         replacement = @module.create_function(name, current_return)
                         replacement_entry = replacement.get_block(replacement.entry_block)
                         if current_return == Adamas::HIR::TypeRef::VOID
                           replacement_entry.terminator = Adamas::HIR::Return.new(nil)
                         else
                           result = Adamas::HIR::Literal.new(replacement.next_value_id, current_return, 1_i64)
                           replacement_entry.add(result)
                           replacement_entry.terminator = Adamas::HIR::Return.new(result.id)
                         end
                         replacement
                       else
                         function.return_type = current_return
                         function
                       end
    register_function_type(name, current_return, allow_explicit_replacement: true)
    current = initializer_return_refinement_spec_source(source, current_function, current_return, mismatch)
    update_prior = replay_source || prior

    initializer_source_recipe_matches?(update_prior, current) &&
      initializer_source_return_update_admitted?(update_prior, current, replay_source)
  end

  private def initializer_return_refinement_spec_source(
    source : MaterializedInitializerSource,
    function : Adamas::HIR::Function,
    return_type : Adamas::HIR::TypeRef,
    mismatch : Symbol? = nil,
  ) : MaterializedInitializerSource
    source_def = source.source_def
    source_arena = source.source_arena
    call_types = source.call_types.try(&.dup)
    case mismatch
    when :def
      source_def = @function_defs.values.find { |candidate| !candidate.same?(source.source_def) }.not_nil!
    when :arena
      source_arena = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new("1")
      ).parse_program.arena
    when :call
      call_types ||= [] of Adamas::HIR::TypeRef
      call_types << Adamas::HIR::TypeRef::INT64
    end

    MaterializedInitializerSource.new(
      function, source.source_name, source_def, source_arena,
      source.namespace, source.bindings.dup,
      source.parameter_types.dup, source.block_parameters.dup, source.heap_block_param,
      copy_initializer_callback_abi(source.callback_abi),
      copy_initializer_callback_source(source.callback_source), return_type,
      source.owner, source.owner_type, source.lowering_namespace,
      source.lowering_bindings.dup, call_types,
      source.call_literals.try(&.dup), source.call_enum_names.try(&.dup),
      source.return_result_invalidated,
    )
  end
end

private def lower_initializer_return_refinement_fixture : Adamas::HIR::AstToHir
  code = <<-CRYSTAL
    class InitializerReturnRefinement
      def initialize(value : Int, offset : Int32 = 3)
        @value = value + offset
      end

      def marker
        1
      end
    end
    InitializerReturnRefinement.new(2)
  CRYSTAL
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  converter.arena = parsed.arena
  main = [] of UInt64
  parsed.roots.each do |id|
    case node = parsed.arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      converter.lower_class(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter
end

private def lower_natural_initializer_replay_fixture : Adamas::HIR::AstToHir
  code = <<-CRYSTAL
    class NaturalInitializerReplayOwner
      def initialize(&@callback)
        @callback
      end
    end
    NaturalInitializerReplayOwner.new { 65 }
  CRYSTAL
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  converter.arena = parsed.arena
  main = [] of UInt64
  parsed.roots.each do |id|
    case node = parsed.arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      converter.lower_class(node)
    else
      main << id.index.to_u64
    end
  end
  # Deliberately stop before the public pending flush: the constructor block
  # refinement has run, while the removed initializer still awaits the real
  # call-demand replay corridor.
  converter.lower_main(main)
  converter
end

describe "materialized initializer return invalidation" do
  it "retires and replays the real captured-block initializer from its source recipe" do
    converter = lower_natural_initializer_replay_fixture
    name = converter.__test_natural_initializer_source_name
    before = converter.__test_natural_initializer_state(name)

    before[:source_name].should eq("NaturalInitializerReplayOwner#initialize$block")
    before[:return_invalidated].should be_true
    before[:function_return].should eq(before[:cached_return])
    before[:live_function_identity].should_not eq(before[:function_identity])
    before[:live_function_has_body].should be_false
    before[:allocator_calls].should_not be_empty
    before[:allocator_calls].all? { |_, type| type == before[:function_return] }.should be_true
    before[:callback_type].not_nil!.should_not eq(Adamas::HIR::TypeRef::VOID)
    before[:function_return].should_not eq(before[:callback_type].not_nil!)
    before[:registry_return].should be_nil

    converter.flush_pending_functions
    after = converter.__test_natural_initializer_state(name)

    after[:source_name].should eq(before[:source_name])
    after[:source_def_identity].should eq(before[:source_def_identity])
    after[:source_arena_identity].should eq(before[:source_arena_identity])
    after[:function_identity].should_not eq(before[:function_identity])
    after[:parameter_types].should eq(before[:parameter_types])
    after[:block_parameters].should eq(before[:block_parameters])
    after[:heap_block_param].should eq(before[:heap_block_param])
    after[:return_invalidated].should be_false
    after[:live_function_identity].should eq(after[:function_identity])
    after[:live_function_has_body].should be_true
    after[:state_completed].should be_true
    after[:function_return].should_not eq(Adamas::HIR::TypeRef::VOID)
    after[:function_return].should_not eq(before[:function_return])
    after[:cached_return].should eq(after[:function_return])
    after[:registry_return].should eq(after[:function_return])
    after[:callback_type].not_nil!.should eq(after[:function_return])
    after[:allocator_calls].should_not be_empty
    after[:allocator_calls].all? { |_, type| type == after[:function_return] }.should be_true

    proc_type = converter.module.get_type_descriptor(after[:function_return]).not_nil!
    proc_type.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc_type.type_params.last?.should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "rejects a return change within one Function generation" do
    converter = lower_initializer_return_refinement_fixture
    name = converter.__test_initializer_return_source_functions.first.name
    converter.__test_initializer_return_update_admitted?(
      name, Adamas::HIR::TypeRef::VOID, Adamas::HIR::TypeRef::INT32, false,
    ).should be_false
  end

  it "rejects a published concrete result mutation without body retirement" do
    converter = lower_initializer_return_refinement_fixture
    name = converter.__test_initializer_return_source_functions.first.name
    converter.__test_initializer_return_update_admitted?(
      name, Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT64, false,
    ).should be_false
  end

  it "admits a changed result only after the exact source body is retired and replayed" do
    converter = lower_initializer_return_refinement_fixture
    name = converter.__test_initializer_return_source_functions.first.name
    converter.__test_initializer_return_update_admitted?(
      name, Adamas::HIR::TypeRef::VOID, Adamas::HIR::TypeRef::INT32, true,
    ).should be_true
  end

  it "uses the rebuilt body result for a concrete-to-concrete replay" do
    converter = lower_initializer_return_refinement_fixture
    name = converter.__test_initializer_return_source_functions.first.name
    converter.__test_initializer_return_update_admitted?(
      name, Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT64, true,
    ).should be_true
  end

  it "rejects a replacement that bypasses source-body invalidation" do
    converter = lower_initializer_return_refinement_fixture
    name = converter.__test_initializer_return_source_functions.first.name
    converter.__test_initializer_return_update_admitted?(
      name, Adamas::HIR::TypeRef::VOID, Adamas::HIR::TypeRef::INT32, true, nil, false,
    ).should be_false
  end

  {% for mismatch in [:def, :arena, :call] %}
    it "rejects a return refinement when the {{ mismatch.id }} provenance changes" do
      converter = lower_initializer_return_refinement_fixture
      name = converter.__test_initializer_return_source_functions.first.name
      converter.__test_initializer_return_update_admitted?(
        name, Adamas::HIR::TypeRef::VOID, Adamas::HIR::TypeRef::INT32, true, {{ mismatch }}
      ).should be_false
    end
  {% end %}
end
