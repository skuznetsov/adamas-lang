require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_unreachable_case(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  defs = [] of Adamas::Compiler::Frontend::DefNode
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
      defs << node
    end
  end
  defs.each { |node| converter.lower_def(node) }
  converter
end

private def unreachable_case_instructions(source : String)
  converter = lower_unreachable_case(source)
  function = converter.module.functions.find { |item| item.name.starts_with?("case_probe") }.not_nil!
  function.blocks.flat_map(&.instructions)
end

private def case_marker_present?(instructions, marker : Int64) : Bool
  instructions.select(Adamas::HIR::Literal).any? { |value| value.type == Adamas::HIR::TypeRef::INT32 && value.int_value == marker }
end

describe "unreachable case body instantiation" do
  it "does not lower a disjoint class branch for a Nil/Bool subject" do
    instructions = unreachable_case_instructions(<<-CRYSTAL)
      class NeverEach
        def each(&); yield 1; end
      end
      def case_probe(flag : Bool)
        value = flag ? nil : true
        case value
        when NeverEach
          value.each { |item| item }
          8101
        when Bool
          41
        else
          42
        end
      end
    CRYSTAL
    case_marker_present?(instructions, 8101).should be_false
    instructions.select(Adamas::HIR::Call).none? { |call| call.method_name.includes?("#each") }.should be_true
  end

  it "requires all comma-separated comparisons to be impossible before skipping" do
    instructions = unreachable_case_instructions(<<-CRYSTAL)
      class NeverA; end
      class NeverB; end
      def case_probe(flag : Bool)
        value = flag ? nil : true
        case value
        when NeverA, NeverB
          8201
        when NeverA, Bool
          8202
        else
          42
        end
      end
    CRYSTAL
    case_marker_present?(instructions, 8201).should be_false
    case_marker_present?(instructions, 8202).should be_true
  end

  it "keeps a descendant branch whose ancestor is a nullable union carrier" do
    instructions = unreachable_case_instructions(<<-CRYSTAL)
      class CaseBase; end
      class CaseChild < CaseBase; end
      def case_probe(value : CaseBase?)
        case value
        when CaseChild
          8301
        else
          42
        end
      end
    CRYSTAL
    case_marker_present?(instructions, 8301).should be_true
  end

  it "keeps a matching generic base branch" do
    instructions = unreachable_case_instructions(<<-CRYSTAL)
      class CaseBox(T); end
      def case_probe(value : CaseBox(Int32)?)
        case value
        when CaseBox
          8401
        else
          42
        end
      end
    CRYSTAL
    case_marker_present?(instructions, 8401).should be_true
  end

  it "keeps predefined ancestors for descriptorless builtin members" do
    instructions = unreachable_case_instructions(<<-CRYSTAL)
      abstract class Object; end
      abstract struct Value; end
      def case_probe(flag : Bool)
        value = flag ? nil : true
        case value
        when Value
          8601
        when Object
          8602
        else
          42
        end
      end
    CRYSTAL
    case_marker_present?(instructions, 8601).should be_true
    case_marker_present?(instructions, 8602).should be_true
  end

  it "preserves effectful value comparisons" do
    instructions = unreachable_case_instructions(<<-CRYSTAL)
      def dynamic_condition; true; end
      def case_probe(flag : Bool)
        value = flag ? nil : true
        case value
        when dynamic_condition
          8501
        else
          42
        end
      end
    CRYSTAL
    case_marker_present?(instructions, 8501).should be_true
    instructions.select(Adamas::HIR::Call).any? { |call| call.method_name.starts_with?("dynamic_condition") }.should be_true
  end
end
