require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

# Test-only access to the generic-class materialization entrypoint.
class Adamas::HIR::AstToHir
  def __test_monomorphize_generic_class(
    base_name : String,
    type_args : Array(String),
    specialized_name : String,
  ) : Nil
    monomorphize_generic_class(base_name, type_args, specialized_name)
  end

  def __test_type_ref_for_generic_proc_ivar(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_annotation_type_ref_for_generic_proc_ivar(
    name : String,
    owner_name : String,
  ) : Adamas::HIR::TypeRef
    annotation_type_ref(name, owner_name)
  end

  def __test_register_type_alias_for_generic_proc_ivar(
    name : String,
    target : String,
  ) : Nil
    register_type_alias(name, target)
  end

  def __test_set_function_def_for_refresh(
    name : String,
    node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    set_function_def_entry(name, node, record_current_arena: false)
    set_function_def_arena(name, arena)
  end

  def __test_canonical_function_def_and_arena_for_refresh(
    name : String,
    node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : {Adamas::Compiler::Frontend::DefNode, Adamas::Compiler::Frontend::ArenaLike}
    canonical_function_def_and_arena_for_name(name, node, arena)
  end

  def __test_lower_generic_proc_ivar_function(name : String) : Nil
    lower_function_if_needed(name)
  end

  def __test_lower_generic_proc_initializer_direct(
    owner_name : String,
    full_name : String,
    call_arg_types : Array(Adamas::HIR::TypeRef),
  ) : Nil
    class_info = @class_info[owner_name]
    base_name = "#{owner_name}#initialize"
    node = @function_defs[base_name]? || raise "missing #{base_name}"
    old_map = @type_param_map
    @type_param_map = {} of String => String
    @subst_cache_gen &+= 1
    begin
      lower_method(
        owner_name,
        class_info,
        node,
        call_arg_types,
        nil,
        nil,
        full_name,
      )
    ensure
      @type_param_map = old_map
      @subst_cache_gen &+= 1
    end
  end
end

private def register_generic_proc_ivar_program(code : String) : Adamas::HIR::AstToHir
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena

  result.roots.each do |expr_id|
    if node = result.arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end

  converter
end

private def parse_single_def_for_refresh(
  code : String,
) : {Adamas::Compiler::Frontend::ArenaLike, Adamas::Compiler::Frontend::DefNode}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  node = result.arena[result.roots.first].as(Adamas::Compiler::Frontend::DefNode)
  {result.arena, node}
end

describe "generic Proc ivar annotations" do
  it "preserves self, key, and value types in a specialized nullable Proc" do
    converter = register_generic_proc_ivar_program(<<-CRYSTAL)
      class CallbackMap(K, V)
        @block : (self, K -> V)?
      end
    CRYSTAL

    value_name = "Adamas::Compiler::Frontend::DefNode"
    specialized_name = "CallbackMap(String, #{value_name})"
    converter.__test_monomorphize_generic_class(
      "CallbackMap",
      ["String", value_name],
      specialized_name,
    )

    class_info = converter.class_info[specialized_name]
    block_ivar = class_info.ivars.find { |ivar| ivar.name == "@block" }
    block_ivar.should_not be_nil

    nullable_desc = converter.module.get_type_descriptor(block_ivar.not_nil!.type)
    nullable_desc.should_not be_nil
    nullable_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)

    nullable_union = converter.union_descriptors.values.find do |descriptor|
      descriptor.name == nullable_desc.not_nil!.name
    end
    nullable_union.should_not be_nil

    variants = nullable_union.not_nil!.variants
    variants.count { |variant| variant.full_name == "Nil" }.should eq(1)
    non_nil_variants = variants.reject { |variant| variant.full_name == "Nil" }
    non_nil_variants.size.should eq(1)

    proc_ref = converter.__test_type_ref_for_generic_proc_ivar(non_nil_variants.first.full_name)
    proc_desc = converter.module.get_type_descriptor(proc_ref)
    proc_desc.should_not be_nil
    proc_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Proc)

    self_ref = converter.__test_type_ref_for_generic_proc_ivar(specialized_name)
    def_node_ref = converter.__test_type_ref_for_generic_proc_ivar(value_name)
    proc_desc.not_nil!.type_params.should eq([
      self_ref,
      Adamas::HIR::TypeRef::STRING,
      def_node_ref,
    ])
  end

  it "keeps the specialized Proc field and return type while lowering ivar assignment and invocation" do
    converter = register_generic_proc_ivar_program(<<-CRYSTAL)
      class CallbackMap(K, V)
        @block : (self, K -> V)?

        def initialize(@block : (self, K -> V)? = nil)
        end

        def invoke(key : K) : V
          @block.not_nil!.call(self, key)
        end
      end
    CRYSTAL

    value_name = "Adamas::Compiler::Frontend::DefNode"
    specialized_name = "CallbackMap(String, #{value_name})"
    converter.__test_monomorphize_generic_class(
      "CallbackMap",
      ["String", value_name],
      specialized_name,
    )

    converter.__test_lower_generic_proc_ivar_function("#{specialized_name}#initialize")
    invoke_name = "#{specialized_name}#invoke$String"
    converter.__test_lower_generic_proc_ivar_function(invoke_name)

    class_info = converter.class_info[specialized_name]
    block_ivar = class_info.ivars.find { |ivar| ivar.name == "@block" }
    block_ivar.should_not be_nil

    nullable_desc = converter.module.get_type_descriptor(block_ivar.not_nil!.type)
    nullable_desc.should_not be_nil
    nullable_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)

    nullable_union = converter.union_descriptors.values.find do |descriptor|
      descriptor.name == nullable_desc.not_nil!.name
    end
    nullable_union.should_not be_nil
    non_nil_variants = nullable_union.not_nil!.variants.reject do |variant|
      variant.full_name == "Nil"
    end
    non_nil_variants.size.should eq(1)

    proc_ref = converter.__test_type_ref_for_generic_proc_ivar(non_nil_variants.first.full_name)
    proc_desc = converter.module.get_type_descriptor(proc_ref)
    proc_desc.should_not be_nil
    proc_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Proc)

    self_ref = converter.__test_type_ref_for_generic_proc_ivar(specialized_name)
    value_ref = converter.__test_type_ref_for_generic_proc_ivar(value_name)
    proc_desc.not_nil!.type_params.should eq([
      self_ref,
      Adamas::HIR::TypeRef::STRING,
      value_ref,
    ])

    initializer = converter.module.functions.find do |function|
      function.name.starts_with?("#{specialized_name}#initialize")
    end
    initializer.should_not be_nil
    block_write = initializer.not_nil!.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::FieldSet) &&
        instruction.as(Adamas::HIR::FieldSet).field_name == "@block"
    end
    block_write.should_not be_nil

    invoke = converter.module.function_by_name(invoke_name)
    invoke.should_not be_nil
    invoke.not_nil!.return_type.should eq(value_ref)

    block_read = invoke.not_nil!.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::FieldGet) &&
        instruction.as(Adamas::HIR::FieldGet).field_name == "@block"
    end
    block_read.should_not be_nil
    block_read.not_nil!.type.should eq(block_ivar.not_nil!.type)

    proc_call = invoke.not_nil!.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::Call) &&
        instruction.as(Adamas::HIR::Call).method_name.includes?("call")
    end
    proc_call.should_not be_nil
    proc_call.not_nil!.type.should eq(value_ref)
  end

  it "does not replace an annotated Proc parameter with an incompatible specialized call type" do
    converter = register_generic_proc_ivar_program(<<-CRYSTAL)
      class CallbackMap(K, V)
        @block : (CallbackMap(K, V), K -> V)?

        def initialize(@block : (CallbackMap(K, V), K -> V)? = nil)
        end
      end
    CRYSTAL

    value_name = "Adamas::Compiler::Frontend::DefNode"
    specialized_name = "CallbackMap(String, #{value_name})"
    converter.__test_monomorphize_generic_class(
      "CallbackMap",
      ["String", value_name],
      specialized_name,
    )

    incompatible_type = converter.__test_type_ref_for_generic_proc_ivar("Nil | #{value_name}")
    emitted_name = "#{specialized_name}#initialize$Nil | #{value_name}"
    converter.__test_lower_generic_proc_initializer_direct(
      specialized_name,
      emitted_name,
      [incompatible_type],
    )

    class_info = converter.class_info[specialized_name]
    block_ivar = class_info.ivars.find { |ivar| ivar.name == "@block" }
    block_ivar.should_not be_nil

    expected_desc = converter.module.get_type_descriptor(block_ivar.not_nil!.type)
    expected_desc.should_not be_nil
    expected_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
    expected_desc.not_nil!.name.should contain("Proc(")
    expected_desc.not_nil!.name.should contain(specialized_name)
    expected_desc.not_nil!.name.should contain("String")
    expected_desc.not_nil!.name.should contain(value_name)

    initializer = converter.module.function_by_name(emitted_name)
    initializer.should_not be_nil
    block_param = initializer.not_nil!.params.find { |param| param.name == "block" }
    block_param.should_not be_nil
    actual_desc = converter.module.get_type_descriptor(block_param.not_nil!.type)
    actual_desc.should_not be_nil
    actual_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
    actual_desc.not_nil!.name.should eq(expected_desc.not_nil!.name)

    incompatible_desc = converter.module.get_type_descriptor(incompatible_type)
    incompatible_desc.should_not be_nil
    actual_desc.not_nil!.name.should_not eq(incompatible_desc.not_nil!.name)
  end

  it "keeps a concrete Hash callback shorthand as a nullable Proc type" do
    converter = register_generic_proc_ivar_program(<<-CRYSTAL)
      class CallbackProbe
      end
    CRYSTAL

    value_name = "Adamas::Compiler::Frontend::DefNode"
    converter.__test_register_type_alias_for_generic_proc_ivar(
      "Legacy::Compiler::Frontend::DefNode",
      value_name,
    )
    plain_alias_ref = converter.__test_type_ref_for_generic_proc_ivar(
      "Other::Compiler::Frontend::DefNode"
    )
    plain_alias_ref.should eq(
      converter.__test_type_ref_for_generic_proc_ivar(value_name)
    )
    callback_name = "(Hash(String, #{value_name}), String -> #{value_name})?"
    callback_ref = converter.__test_type_ref_for_generic_proc_ivar(callback_name)
    callback_desc = converter.module.get_type_descriptor(callback_ref)

    callback_desc.should_not be_nil
    callback_desc.not_nil!.kind.should eq(Adamas::HIR::TypeKind::Union)
    callback_desc.not_nil!.name.should eq(
      "Nil | Proc(Hash(String, #{value_name}), String, #{value_name})"
    )
  end

  it "preserves nullable Proc annotations while materializing Hash itself" do
    converter = register_generic_proc_ivar_program(<<-CRYSTAL)
      class Hash(K, V)
        @block : (self, K -> V)?

        def initialize(@block : (Hash(K, V), K -> V)? = nil)
        end
      end
    CRYSTAL

    value_name = "Adamas::Compiler::Frontend::DefNode"
    specialized_name = "Hash(String, #{value_name})"
    converter.__test_monomorphize_generic_class(
      "Hash",
      ["String", value_name],
      specialized_name,
    )

    field_ref = converter.__test_annotation_type_ref_for_generic_proc_ivar(
      "(self, K -> V)?",
      specialized_name,
    )
    initializer_ref = converter.__test_annotation_type_ref_for_generic_proc_ivar(
      "(Hash(K, V), K -> V)?",
      specialized_name,
    )

    expected_name = "Nil | Proc(#{specialized_name}, String, #{value_name})"
    converter.module.get_type_descriptor(field_ref).not_nil!.name.should eq(expected_name)
    converter.module.get_type_descriptor(initializer_ref).not_nil!.name.should eq(expected_name)
  end

  it "refreshes a scored DefNode and arena after the lookup entry is replaced" do
    converter = register_generic_proc_ivar_program("class RefreshProbe; end")
    old_arena, old_def = parse_single_def_for_refresh(<<-CRYSTAL)
      def choose(value : Int32)
        value
      end
    CRYSTAL
    new_arena, new_def = parse_single_def_for_refresh(<<-CRYSTAL)
      def choose(value : String)
        value
      end
    CRYSTAL

    name = "RefreshProbe#choose$arity1"
    converter.__test_set_function_def_for_refresh(name, old_def, old_arena)
    captured_def = old_def
    captured_arena = old_arena
    converter.__test_set_function_def_for_refresh(name, new_def, new_arena)

    refreshed_def, refreshed_arena = converter.__test_canonical_function_def_and_arena_for_refresh(
      name,
      captured_def,
      captured_arena,
    )

    refreshed_def.same?(new_def).should be_true
    refreshed_def.same?(captured_def).should be_false
    refreshed_arena.same?(new_arena).should be_true
  end

end
