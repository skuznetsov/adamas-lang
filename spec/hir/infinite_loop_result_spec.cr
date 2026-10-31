require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

private def lower_infinite_loop_result(body : String)
  source = "def loop_result(flag : Bool)\n#{body}\nend\n"
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  node = parsed.roots.compact_map { |id| parsed.arena[id].as?(Adamas::Compiler::Frontend::DefNode) }.first
  converter = Adamas::HIR::AstToHir.new(parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  {converter.module, converter.lower_def(node)}
end

private def infinite_loop_return_values(function : Adamas::HIR::Function)
  instructions = function.blocks.flat_map(&.instructions)
  function.blocks.compact_map(&.terminator.as?(Adamas::HIR::Return)).compact_map do |ret|
    instructions.find { |value| value.id == ret.value }
  end
end

describe "infinite loop semantic exit set" do
  it "returns a valued break without a normal Nil exit" do
    _, function = lower_infinite_loop_result("loop do; break 65; end")
    values = infinite_loop_return_values(function)
    values.should_not be_empty
    values.each { |value| value.type.should eq(Adamas::HIR::TypeRef::INT32) }
  end

  it "keeps nested loop break values with their own exit owner" do
    _, function = lower_infinite_loop_result(<<-CRYSTAL)
      loop do
        inner = loop do
          break 65
        end
        break inner
      end
      CRYSTAL
    values = infinite_loop_return_values(function)
    values.should_not be_empty
    values.each { |value| value.type.should eq(Adamas::HIR::TypeRef::INT32) }
  end

  it "includes Nil for a valueless break" do
    _, function = lower_infinite_loop_result("loop do; break; end")
    values = infinite_loop_return_values(function)
    values.should_not be_empty
    values.each { |value| value.type.should eq(Adamas::HIR::TypeRef::NIL) }
  end

  it "merges valued and valueless break results" do
    mod, function = lower_infinite_loop_result(<<-CRYSTAL)
      loop do
        break 65 if flag
        break
      end
      CRYSTAL
    values = infinite_loop_return_values(function)
    values.should_not be_empty
    values.each do |value|
      descriptor = mod.get_type_descriptor(value.type).not_nil!
      descriptor.kind.should eq(Adamas::HIR::TypeKind::Union)
      descriptor.name.split('|').map(&.strip).sort.should eq(["Int32", "Nil"])
    end
  end

  it "does not lower a reachable continuation after a loop with no exits" do
    mod, function = lower_infinite_loop_result("loop do; next; end; 123")
    instructions = function.blocks.flat_map(&.instructions)
    instructions.select(Adamas::HIR::Literal).any? { |value| value.value == 123_i64 }.should be_false
    instructions.any? { |value| mod.get_type_descriptor(value.type).try(&.name) == "NoReturn" }.should be_true
    infinite_loop_return_values(function).should be_empty
  end
end
