require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_distinct_owner_union_guard(names : Array(String)) : Bool
    entry = @function_defs.find { |key, _node| key.starts_with?("GuardLeft#each") }.not_nil!
    types = names.map { |name| type_ref_for_name(name) }
    receiver_type = @module.intern_type(TypeDescriptor.new(TypeKind::Union, names.join(" | "), types))
    function = @module.create_function("distinct_owner_guard", TypeRef::NIL)
    receiver = function.add_param("receiver", receiver_type)
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.register_type(receiver.id, receiver_type)
    block = Adamas::Compiler::Frontend::BlockNode.new(entry[1].span, nil, [] of Adamas::Compiler::Frontend::ExprId)
    result = inline_union_instance_yield(ctx, entry[0], receiver.id,
      [] of ValueId, block, nil)
    result.nil? && function.blocks.all?(&.instructions.empty?)
  end
end

private def lower_distinct_owner_union(source : String, lower_main : Bool = true) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena, sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end
  if lower_main
    converter.lower_main(main)
    converter.flush_pending_functions
  end
  converter
end

describe "distinct instance bodies on union block receivers" do
  [false, true].each do |reverse|
    it "narrows each receiver before expanding its own private helper (reverse=#{reverse})" do
      left = <<-CRYSTAL
        class YieldLeft(T)
          def initialize(@value : T); end
          def each(& : T ->)
            yield left_value
          end
          private def left_value : T; @value; end
        end
      CRYSTAL
      right = <<-CRYSTAL
        class YieldRight(T)
          def initialize(@value : T); end
          def each(& : T ->)
            yield right_value
          end
          private def right_value : T; @value + 1000; end
        end
      CRYSTAL
      owners = reverse ? right + "\n" + left : left + "\n" + right
      converter = lower_distinct_owner_union(owners + <<-CRYSTAL)

        def sum_distinct(flag : Bool) : Int32
          receiver = flag ? YieldLeft(Int32).new(41) : YieldRight(Int32).new(42)
          total = 0
          receiver.each { |value| total += value }
          total
        end
        sum_distinct(true)
      CRYSTAL
      function = converter.module.functions.find { |candidate| candidate.name == "sum_distinct$Bool" }.not_nil!
      instructions = function.blocks.flat_map(&.instructions)
      instructions.select(Adamas::HIR::UnionIs).size.should eq(1)
      instructions.select(Adamas::HIR::UnionUnwrap).size.should eq(2)
      calls = instructions.select(Adamas::HIR::Call)
      calls.map(&.method_name).should contain("YieldLeft(Int32)#left_value")
      calls.map(&.method_name).should contain("YieldRight(Int32)#right_value")
      calls.all? { |call| !call.method_name.includes?(" | ") }.should be_true
      instructions.select(Adamas::HIR::Phi).any? { |phi| phi.type == Adamas::HIR::TypeRef::INT32 }.should be_true
    end
  end

  it "does not emit partial dispatch when a union arm has no matching block method" do
    converter = lower_distinct_owner_union(<<-CRYSTAL, false)
      class GuardLeft
        def each(&); yield 1; end
      end
      class GuardRight
      end
    CRYSTAL
    converter.__test_distinct_owner_union_guard(["GuardLeft", "GuardRight"]).should be_true
  end

  it "does not reuse an overload with an unsatisfied required named argument" do
    converter = lower_distinct_owner_union(<<-CRYSTAL, false)
      class GuardLeft
        def each(&); yield 1; end
      end
      class GuardRight
        def each(*, offset : Int32, &); yield offset; end
      end
    CRYSTAL
    converter.__test_distinct_owner_union_guard(["GuardLeft", "GuardRight"]).should be_true
  end
end
