require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_selected_included_callback_result_bindings(receiver_name : String, other_receiver : String? = nil)
    if receiver = split_generic_base_and_args(receiver_name)
      monomorphize_generic_class(receiver.base, split_generic_type_args(receiver.args), receiver_name)
    end
    receiver_type = type_ref_for_name(receiver_name)
    origin = find_included_module_def_origin_for_owner(
      receiver_name,
      "map",
      0,
      true,
      respect_direct_declarations: true,
      compatible_arg_types: [] of TypeRef,
    )
    return nil unless origin

    selected_name = "#{origin[2]}#map"
    target = SelectedCallTarget.new(selected_name, origin[0], origin[1], origin)
    other_binding = if other_receiver
                      other = find_included_module_def_origin_for_owner(
                        other_receiver, "map", 0, true, compatible_arg_types: [] of TypeRef,
                      ).not_nil!
                      SourceCallBinding.new("#{other[2]}#map", other[0], other[1], [] of SourceCallArgument?)
                    end
    binding = source_call_binding_with_selected_included_origin(
      other_binding,
      target,
      receiver_name,
      synthesize_empty: true,
    ) || raise "expected an empty source binding for the selected map callback"
    {
      binding.included_origin.try(&.[3]),
      source_block_result_bindings(
        origin[0],
        origin[1],
        selected_name,
        receiver_type,
        [] of TypeRef,
        binding,
      ),
    }
  end
end

private def selected_included_callback_result_binding_converter
  source = <<-CRYSTAL
    module Enumerable(T)
      def map(&block : T -> U) : Array(U) forall U
        yield
      end
    end

    class ReceiverTag
    end

    class Hash(K, V, T)
      include Enumerable(Tuple(K, V))
    end

    class MultiHash(K, V, T)
      include Enumerable(Tuple(K, V))
      include Enumerable(Tuple(V, K))
    end

    class ReverseMultiHash(K, V, T)
      include Enumerable(Tuple(V, K))
      include Enumerable(Tuple(K, V))
    end

    module OtherEnumerable(T)
      def map(&block : T -> U) : Array(U) forall U
        yield
      end
    end

    class OtherHash
      include OtherEnumerable(Int32)
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter
end

describe "selected included callback result binding" do
  it "binds Enumerable(Tuple(K, V)) from the exact selected application" do
    origin, bindings = selected_included_callback_result_binding_converter
      .__test_selected_included_callback_result_bindings("Hash(Int32, String, ReceiverTag)")
      .not_nil!

    origin.should eq("Enumerable(Tuple(::Int32, ::String))")
    bindings.should eq({"T" => "Tuple(::Int32, ::String)"})
  end

  it "tracks the selected application when the same module is included twice" do
    first_origin, first_bindings = selected_included_callback_result_binding_converter
      .__test_selected_included_callback_result_bindings("MultiHash(Int32, String, ReceiverTag)")
      .not_nil!
    second_origin, second_bindings = selected_included_callback_result_binding_converter
      .__test_selected_included_callback_result_bindings("ReverseMultiHash(Int32, String, ReceiverTag)")
      .not_nil!

    first_origin.should eq("Enumerable(Tuple(::String, ::Int32))")
    first_bindings.should eq({"T" => "Tuple(::String, ::Int32)"})
    second_origin.should eq("Enumerable(Tuple(::Int32, ::String))")
    second_bindings.should eq({"T" => "Tuple(::Int32, ::String)"})
  end

  it "rejects source arguments for a different declaration" do
    expect_raises(Adamas::HIR::LoweringError, "callback source arguments do not belong to the selected declaration") do
      selected_included_callback_result_binding_converter
        .__test_selected_included_callback_result_bindings("Hash(Int32, String, ReceiverTag)", "OtherHash")
    end
  end
end
