require "spec"
require "../../src/compiler/frontend/parser"

describe "C declaration parameter boundaries" do
  it "keeps an unnamed callback and all following declarations in the lib" do
    source = File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_1.cr"))
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.size.should eq(0)
    program.roots.size.should eq(1)
    lib_node = program.arena[program.roots[0]].as(Adamas::Compiler::Frontend::LibNode)
    body = lib_node.body.not_nil!
    body.map { |id| String.new(program.arena[id].as(Adamas::Compiler::Frontend::FunNode).name) }.should eq(["before", "set_callback", "after"])
    callback = program.arena[body[1]].as(Adamas::Compiler::Frontend::FunNode)
    callback.params.not_nil!.map { |param| String.new(param.type_annotation.not_nil!) }.should eq(["Void*", "(Int32, Int32) -> Int32"])
  end
end

describe "C declaration parameter grammar controls" do
  it "keeps a callback between multiple unnamed scalar parameters" do
    source = File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_2.cr"))
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.size.should eq(0)
    body = program.arena[program.roots[0]].as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
    body.size.should eq(2)
    fun_node = program.arena[body[0]].as(Adamas::Compiler::Frontend::FunNode)
    fun_node.params.not_nil!.map { |param| String.new(param.type_annotation.not_nil!) }.should eq(["Void*", "UInt64", "(Void*, Void*) -> Int32", "UInt64"])
  end

  it "preserves bare multi-input Proc notation on a named parameter" do
    source = File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_3.cr"))
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.size.should eq(0)
    body = program.arena[program.roots[0]].as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
    body.size.should eq(2)
    fun_node = program.arena[body[0]].as(Adamas::Compiler::Frontend::FunNode)
    fun_node.params.not_nil!.map { |param| String.new(param.type_annotation.not_nil!) }.should eq(["Void*", "Int32, Int32 -> Int32"])
    fun_node.params.not_nil!.map { |param| param.name.try { |name| String.new(name) } }.should eq(["ctx", "callback"])
  end

  it "records names on mixed unnamed and named parameters" do
    source = File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_4.cr"))
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.size.should eq(0)
    body = program.arena[program.roots[0]].as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
    body.size.should eq(2)
    fun_node = program.arena[body[0]].as(Adamas::Compiler::Frontend::FunNode)
    fun_node.params.not_nil!.map { |param| String.new(param.type_annotation.not_nil!) }.should eq(["Int64", "Void*", "(Int32) -> Int32"])
    fun_node.params.not_nil!.map { |param| param.name.try { |name| String.new(name) } }.should eq([nil, "ctx", "callback"])
  end

  it "allows newlines within callback input lists" do
    source = File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_5.cr"))
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.size.should eq(0)
    body = program.arena[program.roots[0]].as(Adamas::Compiler::Frontend::LibNode).body.not_nil!
    body.size.should eq(2)
    fun_node = program.arena[body[0]].as(Adamas::Compiler::Frontend::FunNode)
    fun_node.params.not_nil!.size.should eq(3)
  end
end

describe "C callback return type continuation" do
  it "continues the type list without an outer fun parameter delimiter" do
    source = File.read(File.join(__DIR__, "../fixtures/unnamed_fun_callback/grammar_6.cr"))
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.size.should eq(0)
    lib_node = program.arena[program.roots[0]].as(Adamas::Compiler::Frontend::LibNode)
    body = lib_node.body.not_nil!
    body.map { |id| String.new(program.arena[id].as(Adamas::Compiler::Frontend::FunNode).name) }.should eq(["callback", "after"])
    callback = program.arena[body[0]].as(Adamas::Compiler::Frontend::FunNode)
    String.new(callback.return_type.not_nil!).should eq("(\nVoid*,\nInt32) -> Void")
  end
end
