require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

private def tuple_case_width_function(type_name : String, reverse : Bool)
  subject = reverse ? "{1, value}" : "{value, 1}"
  pattern = reverse ? "{1, 0}" : "{0, 1}"
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(<<-CRYSTAL),
      def probe(value : #{type_name}) : Bool
        case #{subject}
        when #{pattern} then true
        else false
        end
      end
      CRYSTAL
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  definition = parsed.arena[parsed.roots.first].as(Adamas::Compiler::Frontend::DefNode)
  converter.register_function(definition)
  converter.lower_def(definition)
end

describe "tuple case subject storage" do
  {"UInt64" => Adamas::HIR::TypeRef::UINT64,
   "Int64" => Adamas::HIR::TypeRef::INT64,
   "Float64" => Adamas::HIR::TypeRef::FLOAT64}.each do |type_name, type_ref|
    [false, true].each do |reverse|
      it "extracts #{type_name} at its subject type in position #{reverse ? 1 : 0}" do
        function = tuple_case_width_function(type_name, reverse)
        gets = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::IndexGet))
        gets.map(&.type).should eq(reverse ? [Adamas::HIR::TypeRef::INT32, type_ref] : [type_ref, Adamas::HIR::TypeRef::INT32])
      end
    end
  end
end
