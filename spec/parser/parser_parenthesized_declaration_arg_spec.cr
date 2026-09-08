require "spec"
require "../../src/compiler/frontend/parser"

private def declaration_argument_call(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  program.roots.size.should eq(1)
  call = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::CallNode)
  {program, call}
end

describe "Parenthesized declaration arguments" do
  it "uses the spaced colon for arbitrary callees, including qualified macros" do
    ["declare(value : ::Int32)", "Owner.declare(value : ::Int32)", "thread_local(value : ::Int32) { 73 }"].each do |source|
      program, call = declaration_argument_call(source)
      call.named_args.should be_nil
      call.args.size.should eq(1)
      decl = program.arena[call.args.first].as(Adamas::Compiler::Frontend::TypeDeclarationNode)
      String.new(decl.name).should eq("value")
      String.new(decl.declared_type).should eq("::Int32")
      decl.value.should be_nil
    end
  end

  it "retains declaration defaults and subsequent arguments" do
    program, call = declaration_argument_call("declare(value : Int32 = 73, enabled : Bool = false)")
    call.args.size.should eq(2)
    call.named_args.should be_nil
    decl = program.arena[call.args[0]].as(Adamas::Compiler::Frontend::TypeDeclarationNode)
    value = program.arena[decl.value.not_nil!].as(Adamas::Compiler::Frontend::NumberNode)
    String.new(value.value).should eq("73")
    second = program.arena[call.args[1]].as(Adamas::Compiler::Frontend::TypeDeclarationNode)
    program.arena[second.value.not_nil!].as(Adamas::Compiler::Frontend::BoolNode).value.should be_false
  end

  it "preserves unspaced named arguments including type-valued arguments" do
    ["declare(value: ::Int32)", "declare(value: 73)", "declare(value:other)"].each do |source|
      _, call = declaration_argument_call(source)
      call.args.should be_empty
      call.named_args.not_nil!.size.should eq(1)
      String.new(call.named_args.not_nil!.first.name).should eq("value")
    end
  end

  it "retains existing typed accessor syntax" do
    program, call = declaration_argument_call("getter(value : Int32)")
    program.arena[call.args.first].should be_a(Adamas::Compiler::Frontend::TypeDeclarationNode)
  end

  it "preserves declarations inside ordinary nested calls" do
    program, outer = declaration_argument_call("outer(1, inner(value : Int32))")
    inner = program.arena[outer.args.last].as(Adamas::Compiler::Frontend::CallNode)
    inner.named_args.should be_nil
    program.arena[inner.args.first].should be_a(Adamas::Compiler::Frontend::TypeDeclarationNode)
  end

  it "rejects spaced declarations in either ternary branch" do
    ["outer(flag ? inner(value : Int32) : other)",
     "outer(flag ? other : inner(value : Int32))"].each do |source|
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      parser.parse_program
      parser.diagnostics.should_not be_empty
    end
  end

  it "preserves adjacent named arguments in ternary branches" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(
      "outer(flag ? inner(value: 1) : inner(value: 2))"))
    parser.parse_program
    parser.diagnostics.should be_empty
  end


  it "restores declaration parsing after a nested ternary argument" do
    program, outer = declaration_argument_call(
      "outer(flag ? inner(other ? 1 : 2) : 3, declare(value : Int32))")
    inner = program.arena[outer.args.last].as(Adamas::Compiler::Frontend::CallNode)
    program.arena[inner.args.first].should be_a(Adamas::Compiler::Frontend::TypeDeclarationNode)
  end


  it "carries ternary declaration restrictions into string interpolation" do
    [%q(outer(flag ? "#{inner(value : Int32)}" : other)),
     %q(outer(flag ? "prefix" "#{inner(value : Int32)}" : other))].each do |source|
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      parser.parse_program
      parser.diagnostics.should_not be_empty
    end
  end

  it "preserves ordinary declaration and ternary named interpolation calls" do
    [%q(outer("#{inner(value : Int32)}")),
     %q(outer(flag ? "#{inner(value: 1)}" : other))].each do |source|
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      parser.parse_program
      parser.diagnostics.should be_empty
    end
  end

end
