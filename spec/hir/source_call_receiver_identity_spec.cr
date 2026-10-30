require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_source_call_receiver_identity(
    call : Adamas::Compiler::Frontend::CallNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
    caller_owner : String,
    class_method : Bool,
  ) : String?
    old_class_method = @current_method_is_class
    begin
      @current_method_is_class = class_method
      with_arena(arena) { source_call_receiver_name(call, caller_owner) }
    ensure
      @current_method_is_class = old_class_method
    end
  end
end

private def source_call_receiver_identity(source : String, class_method : Bool = true)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  call = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::CallNode)
  converter = Adamas::HIR::AstToHir.new(program.arena)
  converter.__test_source_call_receiver_identity(call, program.arena, "ReceiverIdentityBox(Int32)", class_method)
end

describe "source call class receiver identity" do
  it "retains the applied owner for an explicit self receiver" do
    source_call_receiver_identity("self.inner { 1 }").should eq("ReceiverIdentityBox(Int32)")
  end

  it "retains the same applied owner for an implicit class receiver" do
    source_call_receiver_identity("inner { 1 }").should eq("ReceiverIdentityBox(Int32)")
  end

  it "does not turn an instance self receiver into a class value" do
    source_call_receiver_identity("self.inner { 1 }", class_method: false).should be_nil
  end
end
