require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

private def super_default_arena_fixture(module_owner : Bool) : {Adamas::HIR::AstToHir, Adamas::HIR::Function}
  owner_source = if module_owner
                   <<-CRYSTAL
                     module SuperDefaultSource
                       def consume(value : Int32, fallback : Int32 = 42) : Int32
                         fallback
                       end
                     end
                     CRYSTAL
                 else
                   <<-CRYSTAL
                     class SuperDefaultSource
                       def consume(value : Int32, fallback : Int32 = 42) : Int32
                         fallback
                       end
                     end
                     CRYSTAL
                 end
  owner_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(owner_source))
  owner_program = owner_parser.parse_program
  owner_parser.diagnostics.should be_empty
  owner_arena = owner_program.arena
  child_body = module_owner ? "include SuperDefaultSource" : ""
  child_parent = module_owner ? "" : " < SuperDefaultSource"
  # Every ExprId in the owner's arena names a different literal in the child
  # arena. Looking up the default in the caller therefore yields 99, not 42.
  child_source = "99\n" * (owner_arena.size + 4) + <<-CRYSTAL
    class SuperDefaultChild#{child_parent}
      #{child_body}
      def consume(value : Int32) : Int32
        super(value)
      end
    end
    CRYSTAL
  child_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(child_source))
  child_program = child_parser.parse_program
  child_parser.diagnostics.should be_empty
  child_arena = child_program.arena
  converter = Adamas::HIR::AstToHir.new(
    child_arena, sources_by_arena: {
      owner_arena.object_id.to_u64 => owner_source,
      child_arena.object_id.to_u64 => child_source,
    },
  )
  converter.arena = owner_arena
  owner_program.roots.each do |root|
    case node = owner_arena[root]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter.arena = child_arena
  child = child_program.roots.compact_map do |root|
    child_arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end.first
  converter.register_class(child)
  converter.lower_class(child)
  converter.arena.object_id.should eq(child_arena.object_id)
  function = converter.module.function_by_name("SuperDefaultChild#consume$Int32")
  raise "child consume was not lowered" unless function
  {converter, function}
end

describe "super default argument source arenas" do
  {false => "ancestor class", true => "included module"}.each do |module_owner, label|
    it "reads a missing argument from the #{label} definition" do
      converter, function = super_default_arena_fixture(module_owner)
      calls = function.blocks.flat_map(&.instructions).select(Adamas::HIR::Call)
      call = calls.find { |candidate| candidate.method_name.includes?("consume") }
      call.should_not be_nil
      call = call.not_nil!
      call.args.size.should eq(2)
      fallback = function.blocks.flat_map(&.instructions).find { |instruction| instruction.id == call.args[1] }
      fallback.should be_a(Adamas::HIR::Literal)
      fallback.as(Adamas::HIR::Literal).value.should eq(42_i64)
    end
  end
end
