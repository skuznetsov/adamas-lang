require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_proc_receiver_source_signature(type : Adamas::HIR::TypeRef) : String?
    descriptor = @module.get_type_descriptor(type)
    return nil unless descriptor && descriptor.kind == TypeKind::Proc
    proc_source_signature_name(descriptor)
  end

  def __test_proc_receiver_source_identity?(generated_name : String) : Bool
    source_method = method_part(strip_type_suffix(generated_name))
    generated_def = @function_defs[generated_name]?
    generated_arena = @function_def_arenas[generated_name]?
    return false unless generated_def && generated_arena

    source_entry = @function_defs.find do |name, _|
      source_name = strip_type_suffix(name)
      !source_name.starts_with?("Proc(") &&
        method_owner(source_name) == "Proc" &&
        method_part(source_name) == source_method
    end
    return false unless source_entry

    source_arena = @function_def_arenas[source_entry[0]]?
    generated_def.same?(source_entry[1]) &&
      source_arena.try(&.object_id) == generated_arena.object_id
  end

  def __test_proc_member_source_names(method_name : String) : Array(String)
    names = [] of String
    seen_defs = [] of Adamas::Compiler::Frontend::DefNode
    @function_defs.each do |name, def_node|
      source_name = strip_type_suffix(name)
      next if source_name.starts_with?("Proc(")
      next unless method_owner(source_name) == "Proc" && method_part(source_name) == method_name
      next if seen_defs.any? { |seen| seen.same?(def_node) }

      seen_defs << def_node
      names << name
    end
    names.sort
  end

  def __test_bind_proc_member_target!(
    target_name : String,
    source_name : String,
    arena_override : Adamas::Compiler::Frontend::ArenaLike? = nil,
  ) : Nil
    source_def = @function_defs[source_name]? || raise "missing Proc source definition #{source_name}"
    source_arena = arena_override || @function_def_arenas[source_name]? ||
                   raise "missing Proc source arena #{source_name}"
    selected = SelectedCallTarget.new(source_name, source_def, source_arena)
    node = Adamas::Compiler::Frontend::MemberAccessNode.new(
      Adamas::Compiler::Frontend::Span.zero,
      Adamas::Compiler::Frontend::ExprId.new(-1),
      "call".to_slice,
    )
    bind_concrete_proc_member_source_target!(target_name, selected, node)
  end

  def __test_proc_target_matches_source?(target_name : String, source_name : String) : Bool
    target_def = @function_defs[target_name]?
    source_def = @function_defs[source_name]?
    target_arena = @function_def_arenas[target_name]?
    source_arena = @function_def_arenas[source_name]?
    return false unless target_def && source_def && target_arena && source_arena

    target_def.same?(source_def) && target_arena.object_id == source_arena.object_id
  end

  def __test_create_proc_target_body!(target_name : String, source_name : String? = nil) : Nil
    function = @module.create_function(target_name, Adamas::HIR::TypeRef::VOID)
    function.blocks.first.terminator = Adamas::HIR::Return.new
    if source_name
      source_def = @function_defs[source_name]? || raise "missing Proc source definition #{source_name}"
      set_function_def_entry(target_name, source_def, false)
    end
  end
end

private def lower_proc_receiver_materialization(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      classes << node
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
    else
      main << root_id.index.to_u64
    end
  end

  classes.each { |node| converter.lower_class(node) }
  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "concrete Proc receiver materialization" do
  it "keeps the source signature on self for implicit, explicit, zero-arg, and forwarded calls" do
    converter = lower_proc_receiver_materialization(<<-CRYSTAL)
      class ProcReceiverMaterializationOwner
        def self.class_value : Int32
          66
        end

        def instance_value : Int32
          65
        end
      end

      struct Proc
        def self.receiver_class_marker : Int32
          67
        end

        def invoke(other)
          call(other)
        end

        def generic_forward(other : U) forall U
          call(other)
        end

        def invoke_explicit(other)
          self.call(other)
        end

        def invoke_zero
          call
        end

        def invoke_zero_explicit
          self.call
        end

        def forwarded(other)
          invoke(other)
        end
      end

      char_proc = ->(value : Char) { 65 }
      int_proc = ->(value : Int32) { value }
      class_proc = ->(owner : ProcReceiverMaterializationOwner.class) { owner.class_value }
      instance_proc = ->(owner : ProcReceiverMaterializationOwner) { owner.instance_value }
      zero_proc = -> { 67 }

      char_proc.invoke('x')
      char_proc.generic_forward('x')
      char_proc.invoke_explicit('x')
      int_proc.generic_forward(66)
      int_proc.forwarded(66)
      class_proc.invoke(ProcReceiverMaterializationOwner)
      instance_proc.invoke(ProcReceiverMaterializationOwner.new)
      zero_proc.invoke_zero
      zero_proc.invoke_zero_explicit
      Proc.receiver_class_marker
      CRYSTAL

    proc_methods = converter.module.functions.select do |function|
      function.name.starts_with?("Proc(") &&
        (function.name.includes?("#invoke") || function.name.includes?("#forwarded") ||
         function.name.includes?("#generic_forward"))
    end
    proc_methods.should_not be_empty
    ["invoke_zero", "invoke_zero_explicit"].each do |method_name|
      proc_methods.any? do |function|
        function.name == "Proc(Int32)##{method_name}"
      end.should be_true
    end
    converter.module.function_by_name("Proc#invoke").should be_nil
    converter.module.function_by_name("Proc#generic_forward").should be_nil
    converter.module.functions.any? do |function|
      function.name.starts_with?("Proc(") && function.name.includes?("receiver_class_marker")
    end.should be_false
    converter.module.functions.any? do |function|
      function.name.includes?("Proc.receiver_class_marker")
    end.should be_true

    signatures = proc_methods.compact_map do |function|
      self_param = function.params.first?
      self_param.try { |param| converter.__test_proc_receiver_source_signature(param.type) }
    end
    signatures.should contain("Proc(Char, Int32)")
    signatures.should contain("Proc(Int32, Int32)")
    signatures.should contain("Proc(ProcReceiverMaterializationOwner.class, Int32)")
    signatures.should contain("Proc(ProcReceiverMaterializationOwner, Int32)")
    signatures.should contain("Proc(Int32)")

    proc_methods.each do |function|
      converter.__test_proc_receiver_source_identity?(function.name).should be_true
    end

    proc_methods.each do |function|
      calls = function.blocks.flat_map(&.instructions)
        .compact_map(&.as?(Adamas::HIR::Call))
        .select { |call| call.method_name == "Proc#call" }
      if function.name.includes?("#invoke")
        calls.size.should eq(1)
      end
      if function.name.includes?("#invoke_zero")
        calls.size.should eq(1)
        calls.first.args.should be_empty
      end
    end

    class_proc_signature = proc_methods.compact_map do |function|
      param = function.params.first?
      next unless param
      descriptor = converter.module.get_type_descriptor(param.type)
      next unless descriptor && converter.__test_proc_receiver_source_signature(param.type) ==
        "Proc(ProcReceiverMaterializationOwner.class, Int32)"
      descriptor
    end.first
    instance_proc_signature = proc_methods.compact_map do |function|
      param = function.params.first?
      next unless param
      descriptor = converter.module.get_type_descriptor(param.type)
      next unless descriptor && converter.__test_proc_receiver_source_signature(param.type) ==
        "Proc(ProcReceiverMaterializationOwner, Int32)"
      descriptor
    end.first
    class_proc_signature.should_not be_nil
    instance_proc_signature.should_not be_nil
    class_proc_signature.not_nil!.proc_type_literal_slot?(0).should be_true
    instance_proc_signature.not_nil!.proc_type_literal_slot?(0).should be_false
    class_proc_signature.not_nil!.type_params.first.should eq(instance_proc_signature.not_nil!.type_params.first)
  end

  it "does not lower variadic Proc templates before an exact receiver demand" do
    converter = lower_proc_receiver_materialization(<<-CRYSTAL)
      struct Proc
        def variadic_forward(*args : *U) forall U
          call(*args)
        end
      end

      CRYSTAL

    converter.module.function_by_name("Proc#variadic_forward").should be_nil

  end

  it "retains the explicit unsupported-splat diagnostic at the Proc call intrinsic" do
    # This is valid Crystal. Until the intrinsic supports splats, retain the
    # existing fail-closed diagnostic rather than silently dropping arguments.
    expect_raises(Adamas::HIR::LoweringError, /Proc#call requires simple positional arguments/) do
      lower_proc_receiver_materialization(<<-CRYSTAL)
        char_proc = ->(value : Char) { 65 }
        char_proc.call(*{'x'})
        CRYSTAL
    end
  end

  it "consumes annotations on skipped Proc templates before lowering later classes" do
    converter = lower_proc_receiver_materialization(<<-CRYSTAL)
      struct Proc
        @[Primitive(:proc_call)]
        @[Raises]
        def call(*args)
        end
      end

      class ProcReceiverFollowingClass
        def value : Int32
          65
        end
      end

      ProcReceiverFollowingClass.new.value
      CRYSTAL

    following = converter.module.function_by_name("ProcReceiverFollowingClass#value")
    following.should_not be_nil
    converter.module.has_function_with_body?("ProcReceiverFollowingClass#value").should be_true
    converter.module.primitive_for("ProcReceiverFollowingClass#value").should be_nil
  end

  it "reserves a bodyless Proc target for its exact source definition and arena" do
    converter = lower_proc_receiver_materialization(<<-CRYSTAL)
      struct Proc
        def reservation_probe(value : Int32)
          value
        end

        def reservation_probe(value : Char)
          value.ord
        end
      end
      CRYSTAL

    source_names = converter.__test_proc_member_source_names("reservation_probe")
    source_names.size.should eq(2)
    target_name = "Proc(Int32)#reservation_probe$Int32"
    converter.module.has_function_with_body?(target_name).should be_false
    converter.module.function_by_name(target_name).should be_nil

    first_source = source_names.first
    second_source = source_names.last
    converter.__test_bind_proc_member_target!(target_name, first_source)

    converter.module.has_function_with_body?(target_name).should be_false
    converter.__test_proc_target_matches_source?(target_name, first_source).should be_true

    expect_raises(Adamas::HIR::LoweringError, /already has a different source definition/) do
      converter.__test_bind_proc_member_target!(target_name, second_source)
    end
    converter.__test_proc_target_matches_source?(target_name, first_source).should be_true

    wrong_arena = Adamas::Compiler::Frontend::AstArena.new
    expect_raises(Adamas::HIR::LoweringError, /already has a different source arena/) do
      converter.__test_bind_proc_member_target!(target_name, first_source, wrong_arena)
    end
    converter.__test_proc_target_matches_source?(target_name, first_source).should be_true
  end

  it "rejects a materialized Proc target without a complete source binding" do
    converter = lower_proc_receiver_materialization(<<-CRYSTAL)
      struct Proc
        def unbound_body_probe(value : Int32)
          value
        end
      end
      CRYSTAL

    source_name = converter.__test_proc_member_source_names("unbound_body_probe").first
    unbound_target = "Proc(Int32)#unbound_body_probe$Int32"
    converter.__test_create_proc_target_body!(unbound_target)
    converter.module.has_function_with_body?(unbound_target).should be_true

    expect_raises(Adamas::HIR::LoweringError, /body without a complete source binding/) do
      converter.__test_bind_proc_member_target!(unbound_target, source_name)
    end

    partial_target = "Proc(Int32)#partial_body_probe$Int32"
    converter.__test_create_proc_target_body!(partial_target, source_name)
    converter.module.has_function_with_body?(partial_target).should be_true

    expect_raises(Adamas::HIR::LoweringError, /body without a complete source binding/) do
      converter.__test_bind_proc_member_target!(partial_target, source_name)
    end
  end

  it "rejects wrong implicit and explicit Proc arguments against the exact receiver signature" do
    expect_raises(Adamas::HIR::LoweringError, /no overload matches 'Proc\(Char, Int32\)#call'/) do
      lower_proc_receiver_materialization(<<-CRYSTAL)
        struct Proc
          def wrong_implicit
            call("wrong")
          end
        end

        char_proc = ->(value : Char) { 65 }
        char_proc.wrong_implicit
        CRYSTAL
    end

    expect_raises(Adamas::HIR::LoweringError, /no overload matches 'Proc\(Char, Int32\)#call'/) do
      lower_proc_receiver_materialization(<<-CRYSTAL)
        struct Proc
          def wrong_explicit
            self.call("wrong")
          end
        end

        char_proc = ->(value : Char) { 65 }
        char_proc.wrong_explicit
        CRYSTAL
    end

    expect_raises(Adamas::HIR::LoweringError, /wrong number of arguments for 'Proc\(Int32\)#call' \(given 1, expected 0\)/) do
      lower_proc_receiver_materialization(<<-CRYSTAL)
        struct Proc
          def wrong_implicit_arity
            call(65)
          end
        end

        zero_proc = -> { 67 }
        zero_proc.wrong_implicit_arity
        CRYSTAL
    end

    expect_raises(Adamas::HIR::LoweringError, /wrong number of arguments for 'Proc\(Int32\)#call' \(given 1, expected 0\)/) do
      lower_proc_receiver_materialization(<<-CRYSTAL)
        struct Proc
          def wrong_explicit_arity
            self.call(65)
          end
        end

        zero_proc = -> { 67 }
        zero_proc.wrong_explicit_arity
        CRYSTAL
    end
  end

  it "keeps Proc class-literal and instance input slots distinct during admission" do
    expect_raises(Adamas::HIR::LoweringError, /no overload matches 'Proc\(ProcReceiverKindOwner.class, Int32\)#call'/) do
      lower_proc_receiver_materialization(<<-CRYSTAL)
        class ProcReceiverKindOwner
        end

        class_proc = ->(owner : ProcReceiverKindOwner.class) { 65 }
        class_proc.call(ProcReceiverKindOwner.new)
        CRYSTAL
    end

    expect_raises(Adamas::HIR::LoweringError, /no overload matches 'Proc\(ProcReceiverKindOwner, Int32\)#call'/) do
      lower_proc_receiver_materialization(<<-CRYSTAL)
        class ProcReceiverKindOwner
        end

        instance_proc = ->(owner : ProcReceiverKindOwner) { 65 }
        instance_proc.call(ProcReceiverKindOwner)
        CRYSTAL
    end
  end
end
