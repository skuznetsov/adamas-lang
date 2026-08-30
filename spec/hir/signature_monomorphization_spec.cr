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
