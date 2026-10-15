require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_shared_module_union_rejected(names : Array(String), module_owner : String) : Bool
    entry = @function_defs.find do |key, _node|
      parts = parse_method_name(strip_type_suffix(key))
      parts.owner == module_owner && parts.method == "visit"
    end.not_nil!
    types = names.map { |name| type_ref_for_name(name) }
    receiver_type = @module.intern_type(TypeDescriptor.new(TypeKind::Union, names.join(" | "), types))
    function = @module.create_function("shared_module_guard", TypeRef::NIL)
    receiver = function.add_param("receiver", receiver_type)
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.register_type(receiver.id, receiver_type)
    block = Adamas::Compiler::Frontend::BlockNode.new(entry[1].span, nil, [] of Adamas::Compiler::Frontend::ExprId)
    arena = @function_def_arenas[entry[0]]? || @arena
    result = inline_union_shared_module_yield(ctx, entry[0], entry[1], receiver.id,
      [] of ValueId, block, nil, arena)
    result.nil? && function.blocks.all?(&.instructions.empty?)
  end
end

private def lower_shared_module_union(source : String, lower_main : Bool = true) : Adamas::HIR::AstToHir
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
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
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

describe "shared included-module bodies on union receivers" do
  it "narrows self before expanding the body and merges caller assignments" do
    converter = lower_shared_module_union(<<-CRYSTAL)
      module UnionVisit(T)
        def visit(& : T ->)
          yield value
        end
      end
      class UnionLeft(T)
        include UnionVisit(T)
        def initialize(@value : T); end
        def value : T; @value; end
      end
      class UnionRight(T)
        include UnionVisit(T)
        def initialize(@value : T); end
        def value : T; @value; end
      end
      def union_sum(flag : Bool) : Int32
        receiver = flag ? UnionLeft(Int32).new(41) : UnionRight(Int32).new(42)
        total = 0
        receiver.visit { |value| total += value }
        total
      end
      union_sum(true)
    CRYSTAL
    function = converter.module.functions.find { |candidate| candidate.name == "union_sum$Bool" }.not_nil!
    instructions = function.blocks.flat_map(&.instructions)
    instructions.select(Adamas::HIR::UnionIs).size.should eq(1)
    instructions.select(Adamas::HIR::UnionUnwrap).size.should eq(2)
    calls = instructions.select(Adamas::HIR::Call)
    calls.map(&.method_name).should contain("UnionLeft(Int32)#value")
    calls.map(&.method_name).should contain("UnionRight(Int32)#value")
    instructions.select(Adamas::HIR::Phi).any? { |phi| phi.type == Adamas::HIR::TypeRef::INT32 }.should be_true
  end

  it "rejects a direct override before emitting dispatch instructions" do
    converter = lower_shared_module_union(<<-CRYSTAL, false)
      module OverrideVisit(T)
        def visit(& : T ->); yield 1; end
      end
      class OverrideLeft(T)
        include OverrideVisit(T)
      end
      class OverrideRight(T)
        include OverrideVisit(T)
        def visit(& : T ->); yield 2; end
      end
    CRYSTAL
    converter.__test_shared_module_union_rejected(
      ["OverrideLeft(Int32)", "OverrideRight(Int32)"], "OverrideVisit(T)").should be_true
  end

  it "rejects same-name methods from distinct included source definitions" do
    converter = lower_shared_module_union(<<-CRYSTAL, false)
      module FirstVisit(T)
        def visit(& : T ->); yield 1; end
      end
      module SecondVisit(T)
        def visit(& : T ->); yield 2; end
      end
      class FirstVisitor(T)
        include FirstVisit(T)
      end
      class SecondVisitor(T)
        include SecondVisit(T)
      end
    CRYSTAL
    converter.__test_shared_module_union_rejected(
      ["FirstVisitor(Int32)", "SecondVisitor(Int32)"], "FirstVisit(T)").should be_true
  end
end
