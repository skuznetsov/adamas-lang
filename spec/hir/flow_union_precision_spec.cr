require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_seed_flow_union(name : String) : Adamas::HIR::TypeRef
    create_union_type(name)
  end

  def __test_flow_union_members(type_ref : Adamas::HIR::TypeRef) : Array(String)
    if descriptor = @module.get_type_descriptor(type_ref)
      if descriptor.kind == Adamas::HIR::TypeKind::Union
        return split_union_type_name(descriptor.name).sort
      end
    end
    [get_type_name_from_ref(type_ref)]
  end

  def __test_flow_phi_union_members(function : Adamas::HIR::Function) : Array(Array(String))
    members = [] of Array(String)
    function.blocks.each do |block|
      block.instructions.each do |instruction|
        if phi = instruction.as?(Adamas::HIR::Phi)
          members << __test_flow_union_members(phi.type)
        end
      end
    end
    members
  end

  def __test_infer_virtual_flow_return(parent_name : String, method_name : String) : Adamas::HIR::TypeRef
    infer_virtual_return_type_from_class_targets(
      parent_name,
      method_name,
      [] of Adamas::HIR::TypeRef,
      false,
      false,
    )
  end
end

private def lower_flow_union_target(
  source : String,
  target_name : String,
  seed_union : String? = nil,
) : {Adamas::HIR::AstToHir, Adamas::HIR::Function}
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  defs = [] of Adamas::Compiler::Frontend::DefNode
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      defs << node
    end
  end

  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  classes.each { |node| converter.lower_class(node) }
  if union_name = seed_union
    converter.__test_seed_flow_union(union_name)
  end

  target = defs.find { |node| String.new(node.name) == target_name }
  raise "flow-union target #{target_name} not found" unless target
  {converter, converter.lower_def(target)}
end

describe "flow union precision" do
  it "does not widen an if expression to a pre-existing covering union" do
    source = <<-CRYSTAL
      class FlowIfLeft
      end

      class FlowIfRight
      end

      class FlowIfNoise
      end

      def flow_if(flag : Bool, left : FlowIfLeft, right : FlowIfRight)
        if flag
          left
        else
          right
        end
      end
    CRYSTAL
    converter, function = lower_flow_union_target(
      source,
      "flow_if",
      "Nil | FlowIfLeft | FlowIfRight | FlowIfNoise",
    )

    converter.__test_flow_phi_union_members(function).should contain(["FlowIfLeft", "FlowIfRight"])
  end

  it "keeps case arms exact when a broader union was registered first" do
    source = <<-CRYSTAL
      class FlowCaseLeft
      end

      class FlowCaseRight
      end

      class FlowCaseNoise
      end

      def flow_case(flag : Bool, left : FlowCaseLeft, right : FlowCaseRight)
        case flag
        when true
          left
        else
          right
        end
      end
    CRYSTAL
    converter, function = lower_flow_union_target(
      source,
      "flow_case",
      "Nil | FlowCaseLeft | FlowCaseRight | FlowCaseNoise",
    )

    converter.__test_flow_phi_union_members(function).should contain(["FlowCaseLeft", "FlowCaseRight"])
  end

  it "retains a returning Nil rescue arm" do
    source = <<-CRYSTAL
      class FlowRescueValue
      end

      class FlowRescueNoise
      end

      def flow_rescue(value : FlowRescueValue)
        begin
          value
        rescue
          nil
        end
      end
    CRYSTAL
    converter, function = lower_flow_union_target(
      source,
      "flow_rescue",
      "Nil | FlowRescueValue | FlowRescueNoise",
    )

    converter.__test_flow_phi_union_members(function).should contain(["FlowRescueValue", "Nil"])
  end

  it "does not widen inferred virtual method returns to unrelated registered arms" do
    source = <<-CRYSTAL
      abstract class FlowVirtualBase
        abstract def classify
      end

      class FlowVirtualInt < FlowVirtualBase
        def classify : Int32
          1
        end
      end

      class FlowVirtualBool < FlowVirtualBase
        def classify : Bool
          false
        end
      end

      def flow_virtual(receiver : FlowVirtualBase)
        receiver.classify
      end
    CRYSTAL
    converter, _function = lower_flow_union_target(
      source,
      "flow_virtual",
      "Nil | Int32 | String | Bool",
    )

    inferred = converter.__test_infer_virtual_flow_return("FlowVirtualBase", "classify")
    converter.__test_flow_union_members(inferred).should eq(["Bool", "Int32"])
  end

  it "keeps inline non-local return values exact" do
    source = <<-CRYSTAL
      class FlowInlineLeft
      end

      class FlowInlineRight
      end

      class FlowInlineNoise
      end

      class FlowInlineExit
      end

      def flow_yield(flag : Bool, left : FlowInlineLeft, right : FlowInlineRight, &)
        if flag
          return left
        else
          yield
          return right
        end
      end

      def flow_inline(flag : Bool, block_exit : Bool, left : FlowInlineLeft, right : FlowInlineRight, exit_value : FlowInlineExit)
        flow_yield(flag, left, right) do
          return exit_value if block_exit
        end
      end
    CRYSTAL
    converter, function = lower_flow_union_target(
      source,
      "flow_inline",
      "Nil | FlowInlineLeft | FlowInlineRight | FlowInlineNoise | FlowInlineExit",
    )

    converter.__test_flow_phi_union_members(function).should contain(["FlowInlineLeft", "FlowInlineRight"])
  end

  it "flattens nested union arms and discards non-returning branches" do
    nested_source = <<-CRYSTAL
      def flow_nested(flag : Bool, value : Int32 | String, other : Bool)
        if flag
          value
        else
          other
        end
      end
    CRYSTAL
    nested_converter, nested_function = lower_flow_union_target(
      nested_source,
      "flow_nested",
      "Nil | Int32 | String | Bool | Float64",
    )
    nested_converter.__test_flow_phi_union_members(nested_function).should contain(["Bool", "Int32", "String"])

    subtype_source = <<-CRYSTAL
      class FlowSubtypeBase
      end

      class FlowSubtypeChild < FlowSubtypeBase
      end

      def flow_subtype(flag : Bool, base : FlowSubtypeBase, child : FlowSubtypeChild)
        if flag
          base
        else
          child
        end
      end
    CRYSTAL
    subtype_converter, subtype_function = lower_flow_union_target(subtype_source, "flow_subtype")
    subtype_converter.__test_flow_phi_union_members(subtype_function).should contain(["FlowSubtypeBase"])

    bottom_source = <<-CRYSTAL
      class FlowBottomValue
      end

      def flow_bottom(flag : Bool, value : FlowBottomValue)
        if flag
          value
        else
          raise "no value"
        end
      end
    CRYSTAL
    bottom_converter, bottom_function = lower_flow_union_target(bottom_source, "flow_bottom")
    bottom_converter.__test_flow_union_members(bottom_function.return_type).should eq(["FlowBottomValue"])
  end
end
