require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  private record SpecClassvarPendingEvent,
    key : String,
    producer : String,
    source_arena_id : UInt64,
    owner : String,
    function_present : Bool,
    function_has_body : Bool,
    owner_handle_cached : Bool,
    in_progress : Bool,
    state_completed : Bool,
    partial_blocks : Int32,
    partial_instructions : Int32,
    blocks_before_suspend : Int32,
    instructions_before_suspend : Int32,
    restored_arena_id : UInt64,
    restored_class : String?,
    restored_method : String?,
    restored_method_is_class : Bool,
    restored_namespace : String?

  @spec_classvar_pending_events = [] of SpecClassvarPendingEvent
  @spec_classvar_ambient_key : String? = nil
  @spec_classvar_wrong_arena : Adamas::Compiler::Frontend::ArenaLike? = nil
  @spec_classvar_wrong_owner : String? = nil
  @spec_classvar_wrong_namespace : String? = nil
  @spec_classvar_pending_function : String? = nil
  @spec_classvar_pending_expr_id : Adamas::Compiler::Frontend::ExprId? = nil
  @spec_classvar_pending_source : ForceLowerExactSourceBinding? = nil
  @spec_classvar_pending_producer : String? = nil
  @spec_classvar_pending_injected = false
  @spec_classvar_blocks_before_suspend = 0
  @spec_classvar_instructions_before_suspend = 0

  def __test_register_class_methods(node : Adamas::Compiler::Frontend::ClassNode) : Nil
    owner = class_name_from_node(node) || raise "class name unavailable"
    previous_class = @current_class
    @current_class = owner
    if body = node.body
      body.each do |member_id|
        member = @arena[member_id]
        register_function(member) if member.is_a?(Adamas::Compiler::Frontend::DefNode)
      end
    end
  ensure
    @current_class = previous_class
  end

  def __test_publish_deferred_classvar_inits : Nil
    @deferred_classvar_inits.each do |entry|
      name = extract_deferred_classvar_name(entry.arena, entry.expr_id)
      next unless name
      @classvar_lazy_init_info["#{entry.owner_class}::#{name}"] = entry
    end
  end

  def __test_registered_source_names(definition : Adamas::Compiler::Frontend::DefNode) : Array(String)
    names = [] of String
    definition_name = String.new(definition.name)
    @function_defs.each do |name, candidate|
      names << name if candidate.same?(definition) || String.new(candidate.name) == definition_name
    end
    names.sort
  end

  def __test_classvar_caller_context(arena : Adamas::Compiler::Frontend::ArenaLike) : LoweringContext
    function = @module.create_function("__classvar_transaction_spec_caller", TypeRef::VOID)
    LoweringContext.new(function, @module, arena)
  end

  def __test_classvar_init_name(owner : String, name : String) : String
    classvar_init_func_name(owner, name)
  end

  def __test_classvar_init_expr_id(key : String) : ExprId
    @classvar_lazy_init_info[key].expr_id
  end

  def __test_inject_classvar_pending_once(
    key : String,
    func_name : String,
    expr_id : Adamas::Compiler::Frontend::ExprId,
    producer : String,
    producer_def : Adamas::Compiler::Frontend::DefNode,
    producer_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    @spec_classvar_ambient_key = key
    @spec_classvar_pending_function = func_name
    @spec_classvar_pending_expr_id = expr_id
    @spec_classvar_pending_producer = producer
    @spec_classvar_pending_source = ForceLowerExactSourceBinding.new(producer_def, producer_arena, producer)
  end

  def __test_classvar_source_node_kinds(
    key : String,
    foreign_arena : Adamas::Compiler::Frontend::AstArena,
  ) : Tuple(String, String)
    info = @classvar_lazy_init_info[key]
    {info.arena[info.expr_id].class.name, foreign_arena[info.expr_id].class.name}
  end

  def __test_classvar_init_status(name : String) : Tuple(Bool, Bool, Bool, Bool, Bool, Int32, Int32, UInt64)
    function = @module.function_by_name(name)
    instructions = function.try(&.blocks.flat_map(&.instructions)) || [] of Value
    {
      !function.nil?,
      @module.has_function_with_body?(name),
      __test_classvar_init_handle_owned?(name),
      @classvar_init_functions_in_progress.includes?(name),
      function_state(name).completed?,
      function.try(&.blocks.size) || 0,
      instructions.size,
      @module.hir_body_revision,
    }
  end

  def __test_classvar_pending_events : Array(SpecClassvarPendingEvent)
    @spec_classvar_pending_events
  end

  def __test_set_classvar_wrong_ambient(
    key : String,
    arena : Adamas::Compiler::Frontend::ArenaLike,
    owner : String,
    namespace : String?,
  ) : Nil
    @spec_classvar_ambient_key = key
    @spec_classvar_wrong_arena = arena
    @spec_classvar_wrong_owner = owner
    @spec_classvar_wrong_namespace = namespace
  end

  def __test_set_ambient_context(
    arena : Adamas::Compiler::Frontend::ArenaLike,
    owner : String?,
    method : String?,
    namespace : String?,
  ) : Nil
    @arena = arena
    @current_class = owner
    @current_method = method
    @current_method_is_class = false
    @current_namespace_override = namespace
  end

  def __test_ambient_context : Tuple(UInt64, String?, String?, Bool, String?)
    {@arena.object_id.to_u64, @current_class, @current_method,
     @current_method_is_class, @current_namespace_override}
  end

  def __test_force_classvar_init_again(key : String, name : String, caller_ctx : LoweringContext) : String?
    ensure_classvar_init_function(key, name, caller_ctx)
  rescue pending : ExactResultPending
    pending.producer
  end

  def __test_classvar_init_handle_owned?(name : String) : Bool
    function = @module.function_by_name(name)
    owned = @classvar_init_function_handles[name]?
    !!(function && owned && function.same?(owned))
  end

  def __test_classvar_partial_shape_before_suspend : Tuple(Int32, Int32)
    {@spec_classvar_blocks_before_suspend, @spec_classvar_instructions_before_suspend}
  end

  def lower_expr(ctx : LoweringContext, expr_id : ExprId) : ValueId
    if !@spec_classvar_pending_injected &&
       ctx.function.name == @spec_classvar_pending_function &&
       expr_id == @spec_classvar_pending_expr_id
      @spec_classvar_pending_injected = true
      @spec_classvar_blocks_before_suspend = ctx.function.blocks.size
      @spec_classvar_instructions_before_suspend = ctx.function.blocks.sum(&.instructions.size)
      raise ExactResultPending.new(
        ctx.function.name,
        @spec_classvar_pending_producer.not_nil!,
        @spec_classvar_pending_source.not_nil!,
      )
    end

    previous_def
  end

  def __test_seed_unowned_completed_classvar_function(name : String) : Function
    function = @module.create_function(name, TypeRef::VOID)
    function.blocks[function.entry_block].terminator = Return.new(nil)
    set_function_state(name, FunctionLoweringState::Completed)
    function
  end

  def __test_reenter_classvar_initializer(
    key : String,
    name : String,
    caller_ctx : LoweringContext,
  ) : Tuple(Bool, Bool, Bool)
    partial = @module.create_function(name, TypeRef::VOID)
    @classvar_init_functions_in_progress << name
    begin
      ensure_classvar_init_function(key, name, caller_ctx)
      current = @module.function_by_name(name)
      {current.try(&.same?(partial)) || false,
       @classvar_init_functions_in_progress.includes?(name),
       __test_classvar_init_handle_owned?(name)}
    ensure
      @classvar_init_functions_in_progress.delete(name)
      @module.remove_function(name) if @module.function_by_name(name).try(&.same?(partial))
    end
  end

  private def ensure_classvar_init_function(
    key : String,
    func_name : String,
    caller_ctx : LoweringContext,
  )
    saved_arena = @arena
    saved_class = @current_class
    saved_method = @current_method
    saved_method_is_class = @current_method_is_class
    saved_namespace = @current_namespace_override
    override_ambient = key == @spec_classvar_ambient_key
    if override_ambient
      @arena = @spec_classvar_wrong_arena.not_nil!
      @current_class = @spec_classvar_wrong_owner
      @current_method = "ambient_sentinel"
      @current_method_is_class = false
      @current_namespace_override = @spec_classvar_wrong_namespace
    end

    begin
      previous_def
    rescue pending : ExactResultPending
      info = @classvar_lazy_init_info[key]
      function = @module.function_by_name(func_name)
      instructions = function.try(&.blocks.flat_map(&.instructions)) || [] of Value
      @spec_classvar_pending_events << SpecClassvarPendingEvent.new(
        key,
        pending.producer,
        info.arena.object_id.to_u64,
        info.owner_class,
        !function.nil?,
        @module.has_function_with_body?(func_name),
        __test_classvar_init_handle_owned?(func_name),
        @classvar_init_functions_in_progress.includes?(func_name),
        function_state(func_name).completed?,
        function.try(&.blocks.size) || 0,
        instructions.size,
        @spec_classvar_blocks_before_suspend,
        @spec_classvar_instructions_before_suspend,
        @arena.object_id.to_u64,
        @current_class,
        @current_method,
        @current_method_is_class,
        @current_namespace_override,
      )
      raise pending
    ensure
      @arena = saved_arena
      @current_class = saved_class
      @current_method = saved_method
      @current_method_is_class = saved_method_is_class
      @current_namespace_override = saved_namespace
    end
  end
end

private def lazy_classvar_init_pending_fixture : Tuple(
  Adamas::HIR::AstToHir,
  Adamas::Compiler::Frontend::AstArena,
  Adamas::Compiler::Frontend::AstArena,
  String,
  Adamas::Compiler::Frontend::DefNode,
  String,
)
  source = <<-CRYSTAL
    class LazyInitPendingTarget
      def initialize
        nil
      end
    end

    class LazyInitPendingOwner
      @@target = LazyInitPendingTarget.new
    end
  CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.arena = arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  target_initializer = nil.as(Adamas::Compiler::Frontend::DefNode?)
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
      converter.register_class(node)
      converter.__test_register_class_methods(node)
      if String.new(node.name) == "LazyInitPendingTarget"
        node.body.not_nil!.each do |member_id|
          member = arena[member_id]
          if definition = member.as?(Adamas::Compiler::Frontend::DefNode)
            target_initializer = definition if String.new(definition.name) == "initialize"
          end
        end
      end
    end
  end
  classes.size.should eq(2)
  target_initializer.should_not be_nil
  converter.__test_publish_deferred_classvar_inits

  foreign_source = Array.new(arena.size + 8) { "0" }.join("\n")
  foreign_arena = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(foreign_source),
  ).parse_program.arena.as(Adamas::Compiler::Frontend::AstArena)

  target_initializer_name = converter.__test_registered_source_names(target_initializer.not_nil!).first
  target_initializer_name.should_not be_empty
  {converter, arena, foreign_arena, target_initializer_name, target_initializer.not_nil!,
   "LazyInitPendingOwner::target"}
end

describe "lazy classvar initializer suspension transaction" do
  it "keeps reentrant construction behind the active cycle guard" do
    converter, arena, _, _, _, key = lazy_classvar_init_pending_fixture
    init_name = converter.__test_classvar_init_name("LazyInitPendingOwner", "target")
    caller = converter.__test_classvar_caller_context(arena)

    reentry = converter.__test_reenter_classvar_initializer(key, init_name, caller)
    reentry[0].should be_true
    reentry[1].should be_true
    reentry[2].should be_false
    converter.module.has_function?(init_name).should be_false
  end

  it "rejects and preserves a completed same-name function without owned identity" do
    converter, arena, _, _, _, key = lazy_classvar_init_pending_fixture
    init_name = converter.__test_classvar_init_name("LazyInitPendingOwner", "target")
    caller = converter.__test_classvar_caller_context(arena)
    foreign_function = converter.__test_seed_unowned_completed_classvar_function(init_name)

    error = expect_raises(Adamas::HIR::LoweringError) do
      converter.__test_force_classvar_init_again(key, init_name, caller)
    end
    error.details.should contain("cannot rebuild unowned classvar initializer body")
    converter.module.function_by_name(init_name).not_nil!.same?(foreign_function).should be_true
    converter.module.has_function_with_body?(init_name).should be_true
    converter.__test_classvar_init_status(init_name)[4].should be_true
    converter.__test_classvar_init_status(init_name)[2].should be_false
  end

  it "discards a suspended body, restores ambient state, and retries the exact owner arena" do
    converter, arena, foreign_arena, producer_name, producer_def, key = lazy_classvar_init_pending_fixture
    init_name = converter.__test_classvar_init_name("LazyInitPendingOwner", "target")
    source_node_kind, foreign_node_kind = converter.__test_classvar_source_node_kinds(key, foreign_arena)
    source_node_kind.should eq("Adamas::Compiler::Frontend::AssignNode")
    foreign_node_kind.should eq("Adamas::Compiler::Frontend::NumberNode")
    converter.__test_set_classvar_wrong_ambient(key, foreign_arena, "ForeignAmbientOwner", "ForeignAmbientNamespace")
    converter.__test_set_ambient_context(
      foreign_arena,
      "CallerAmbientOwner",
      "caller_sentinel",
      "CallerAmbientNamespace",
    )
    ambient_before = converter.__test_ambient_context

    converter.__test_inject_classvar_pending_once(
      key,
      init_name,
      converter.__test_classvar_init_expr_id(key),
      producer_name,
      producer_def,
      arena,
    )
    converter.__test_force_classvar_init_again(
      key,
      init_name,
      converter.__test_classvar_caller_context(arena),
    ).should eq(producer_name)

    events = converter.__test_classvar_pending_events
    events.should_not be_empty
    pending = events.first
    pending.key.should eq(key)
    pending.producer.should eq(producer_name)
    pending.source_arena_id.should eq(arena.object_id.to_u64)
    pending.owner.should eq("LazyInitPendingOwner")
    pending.function_present.should be_false
    pending.function_has_body.should be_false
    pending.owner_handle_cached.should be_false
    pending.in_progress.should be_false
    pending.state_completed.should be_false
    pending.partial_blocks.should eq(0)
    pending.partial_instructions.should eq(0)
    blocks_before_suspend, instructions_before_suspend = converter.__test_classvar_partial_shape_before_suspend
    blocks_before_suspend.should be > 0
    instructions_before_suspend.should be > 0
    pending.restored_arena_id.should eq(foreign_arena.object_id.to_u64)
    pending.restored_class.should eq("ForeignAmbientOwner")
    pending.restored_method.should eq("ambient_sentinel")
    pending.restored_method_is_class.should be_false
    pending.restored_namespace.should eq("ForeignAmbientNamespace")
    converter.__test_ambient_context.should eq(ambient_before)

    failed_status = converter.__test_classvar_init_status(init_name)
    failed_status[0].should be_false
    failed_status[1].should be_false
    failed_status[2].should be_false
    failed_status[3].should be_false
    failed_status[4].should be_false

    converter.__test_set_classvar_wrong_ambient(key, foreign_arena, "ForeignAmbientOwner", nil)
    converter.__test_set_ambient_context(
      foreign_arena,
      "CallerAmbientOwner",
      "caller_sentinel",
      nil,
    )
    retry_ambient = converter.__test_ambient_context
    converter.__test_force_classvar_init_again(
      key,
      init_name,
      converter.__test_classvar_caller_context(arena),
    ).should be_nil

    status = converter.__test_classvar_init_status(init_name)
    status[0].should be_true
    status[1].should be_true
    status[2].should be_true
    status[3].should be_false
    status[4].should be_true
    converter.__test_classvar_init_handle_owned?(init_name).should be_true
    converter.__test_ambient_context.should eq(retry_ambient)
    init_function = converter.module.function_by_name(init_name).not_nil!
    writes = init_function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::ClassVarSet))
    owner_write = writes.find do |write|
      write.class_name == "LazyInitPendingOwner" && write.var_name == "target"
    end
    owner_write.should_not be_nil
    owner_write.not_nil!.type.should eq(converter.class_info["LazyInitPendingTarget"].type_ref)
    flag_write = writes.find do |write|
      write.class_name == "__init_flags" && write.var_name == "#{init_name}$flag"
    end
    flag_write.should_not be_nil

    function_count = converter.module.functions.size
    body_revision = converter.module.hir_body_revision
    converter.__test_force_classvar_init_again(key, init_name,
      converter.__test_classvar_caller_context(arena))
    repeated_status = converter.__test_classvar_init_status(init_name)
    repeated_status[0].should be_true
    repeated_status[1].should be_true
    repeated_status[2].should be_true
    repeated_status[3].should be_false
    repeated_status[4].should be_true
    converter.module.functions.size.should eq(function_count)
    converter.module.hir_body_revision.should eq(body_revision)
    converter.module.function_by_name(init_name).not_nil!.same?(init_function).should be_true
    converter.__test_classvar_pending_events.size.should eq(1)
    converter.__test_ambient_context.should eq(retry_ambient)
  end
end
