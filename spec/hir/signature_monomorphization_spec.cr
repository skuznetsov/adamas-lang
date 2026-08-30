require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_signature_monomorphized?(name : String) : Bool
    @monomorphized.includes?(name)
  end

  def __test_signature_function_names(base_name : String) : Array(String)
    @function_defs.keys.select { |name| name.starts_with?(base_name) }
  end

  def __test_demand_signature_type(name : String) : Nil
    ensure_monomorphized_type(type_ref_for_name(name))
  end

  def __test_lower_signature_function(name : String) : Nil
    lower_function_if_needed(name)
  end

  def __test_signature_type_name(type : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type)
  end

  def __test_clear_signature_param_caches : Nil
    @function_param_infos.clear
    @function_param_infos_by_def_id.clear
  end

  def __test_template_method_matches_suffix?(
    def_node : Adamas::Compiler::Frontend::DefNode,
    def_arena : Adamas::Compiler::Frontend::ArenaLike,
    suffix : String,
  ) : Bool
    template_method_matches_suffix?(def_node, def_arena, suffix)
  end

  def __test_clear_nominal_type_cache : Nil
    @type_cache.clear
    @type_cache_keys_by_component.clear
    @type_cache_keys_by_generic_prefix.clear
  end
end

describe "function signature registration" do
  it "preserves a concrete generic type without materializing its class" do
    source = <<-CRYSTAL
      class Box(T)
        def value : T
          0.as(T)
        end
      end

      def consume(value : Box(Int32)) : Box(Int32)
        value
      end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source)
    )
    result = parser.parse_program
    converter = Adamas::HIR::AstToHir.new(result.arena)
    converter.arena = result.arena

    box = result.roots.compact_map do |expr_id|
      result.arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
    end.first
    consume = result.roots.compact_map do |expr_id|
      result.arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
    end.first

    converter.register_class(box)
    converter.flush_pending_monomorphizations
    converter.register_function(consume)

    names = converter.__test_signature_function_names("consume")
    names.any? { |name| name.includes?("Box") && name.includes?("Int32") }.should be_true
    converter.__test_signature_monomorphized?("Box(Int32)").should be_false
    converter.class_info.has_key?("Box(Int32)").should be_false

    converter.__test_demand_signature_type("Box(Int32)")
    converter.__test_signature_monomorphized?("Box(Int32)").should be_true
    converter.class_info.has_key?("Box(Int32)").should be_true
  end

  it "keeps generic method declarations while deferring bodies and referenced types" do
    source = <<-CRYSTAL
      class Leaf(T)
      end

      class Box(T)
        class Inner(U)
        end

        def unused : Leaf(T)
          0.as(Leaf(T))
        end

        def nested : Inner(T)
          0.as(Inner(T))
        end

        def pick(value : Int32) : Int32
          value
        end

        def pick(value : String) : String
          value
        end
      end

      class Box(T)
        def pick(value : Bool) : Bool
          value
        end
      end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source)
    )
    result = parser.parse_program
    converter = Adamas::HIR::AstToHir.new(result.arena)
    converter.arena = result.arena

    result.roots.each do |expr_id|
      if node = result.arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
        converter.register_class(node)
      end
    end
    converter.flush_pending_monomorphizations

    converter.__test_demand_signature_type("Box(Int32)")
    converter.__test_signature_monomorphized?("Box(Int32)").should be_true
    converter.__test_signature_monomorphized?("Leaf(Int32)").should be_false
    converter.__test_signature_function_names("Box(Int32)#unused").should_not be_empty
    converter.__test_signature_function_names("Box(Int32)#nested").should_not be_empty
    converter.__test_signature_function_names("Box(Int32)#pick").should_not be_empty
    converter.module.functions.none? do |registered|
      registered.name.starts_with?("Box(Int32)#unused") ||
        registered.name.starts_with?("Box(Int32)#nested") ||
        registered.name.starts_with?("Box(Int32)#pick")
    end.should be_true

    converter.__test_lower_signature_function("Box(Int32)#unused")

    function = converter.module.function_by_name("Box(Int32)#unused")
    function.should_not be_nil
    function.not_nil!.blocks.any? { |block| !block.instructions.empty? }.should be_true
    converter.__test_signature_type_name(function.not_nil!.return_type).should eq("Leaf(Int32)")

    converter.__test_lower_signature_function("Box(Int32)#nested")
    nested = converter.module.function_by_name("Box(Int32)#nested")
    nested.should_not be_nil
    converter.__test_signature_type_name(nested.not_nil!.return_type).should eq("Box::Inner(Int32)")

    converter.__test_lower_signature_function("Box(Int32)#pick$Int32")
    int_pick = converter.module.function_by_name("Box(Int32)#pick$Int32")
    int_pick.should_not be_nil
    int_pick.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT32)

    converter.__test_lower_signature_function("Box(Int32)#pick$String")
    string_pick = converter.module.function_by_name("Box(Int32)#pick$String")
    string_pick.should_not be_nil
    string_pick.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::STRING)

    converter.__test_lower_signature_function("Box(Int32)#pick$Bool")
    bool_pick = converter.module.function_by_name("Box(Int32)#pick$Bool")
    bool_pick.should_not be_nil
    bool_pick.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::BOOL)

    converter.__test_demand_signature_type("Leaf(Int32)")
    converter.__test_signature_monomorphized?("Leaf(Int32)").should be_true
    function.not_nil!.return_type.should eq(converter.class_info["Leaf(Int32)"].type_ref)
  end

  it "uses the template arena when suffix metadata has only spans" do
    reopening_source = <<-CRYSTAL
      class Box(T)
        def pick(value : String) : String
          value
        end
      end
    CRYSTAL
    trap_source = <<-CRYSTAL
      class Box(T)
        def pick(value : Object) : Object
          value
        end
      end
    CRYSTAL

    results = [reopening_source, trap_source].map do |source|
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(source)
      )
      parser.parse_program
    end

    reopening_class = results[0].roots.compact_map do |expr_id|
      results[0].arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
    end.first
    reopening_def = reopening_class.body.not_nil!.compact_map do |expr_id|
      results[0].arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
    end.first
    original_param = reopening_def.params.not_nil!.first
    reopening_def.params.not_nil![0] = Adamas::Compiler::Frontend::Parameter.new(
      original_param.name,
      original_param.external_name,
      nil,
      original_param.default_value,
      original_param.span,
      original_param.name_span,
      original_param.external_name_span,
      original_param.type_span,
      original_param.default_span,
      original_param.is_splat,
      original_param.is_double_splat,
      original_param.is_block,
      original_param.is_instance_var,
    )

    converter = Adamas::HIR::AstToHir.new(results[1].arena)
    converter.__test_clear_signature_param_caches
    converter.__test_template_method_matches_suffix?(
      reopening_def,
      results[0].arena,
      "String",
    ).should be_true

    converter.__test_clear_signature_param_caches
    converter.__test_template_method_matches_suffix?(
      reopening_def,
      results[1].arena,
      "String",
    ).should be_false
  end

  it "keeps reference ivar annotations nominal during final layout" do
    source = <<-CRYSTAL
      class Array(T)
      end

      struct Pair(T)
        @left : T
        @right : T
      end

      class Holder
        @value : Array(Int32)
        @pair : ::Pair(Int64)
      end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source)
    )
    result = parser.parse_program
    converter = Adamas::HIR::AstToHir.new(result.arena)
    converter.arena = result.arena

    result.roots.each do |expr_id|
      if node = result.arena[expr_id].as?(Adamas::Compiler::Frontend::ClassNode)
        converter.register_class(node)
      end
    end
    converter.flush_pending_monomorphizations
    converter.class_info["Holder"].ivars.size.should eq(2)
    converter.__test_signature_monomorphized?("Array(Int32)").should be_false
    converter.__test_signature_monomorphized?("Pair(Int64)").should be_false

    converter.__test_clear_nominal_type_cache
    converter.fixup_inherited_ivars

    converter.__test_signature_monomorphized?("Array(Int32)").should be_false
    converter.class_info.has_key?("Array(Int32)").should be_false
    converter.__test_signature_monomorphized?("Pair(Int64)").should be_true
    converter.class_info["Pair(Int64)"].size.should eq(16)
  end
end
