require "spec"
require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/macro_expander"

class Adamas::Compiler::Semantic::MacroExpander
  def __test_emit_error(message : String, location : Adamas::Compiler::Frontend::ExprId?) : Nil
    emit_error(message, location)
  end
end

describe "MacroExpander diagnostic recovery" do
  it "keeps the error-location path free of nullable arena lookup" do
    source = File.read(File.expand_path("../../src/compiler/semantic/macro_expander.cr", __DIR__))
    source.should contain("location.null_ptr?")
    source.should_not contain("@arena[location]?")
  end

  it "uses a default span for an invalid source location" do
    program = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("1\n")
    ).parse_program
    expander = Adamas::Compiler::Semantic::MacroExpander.new(program, program.arena)

    expander.__test_emit_error("invalid location", Adamas::Compiler::Frontend::ExprId.new(-1))

    expander.diagnostics.size.should eq(1)
    diagnostic = expander.diagnostics.first
    diagnostic.primary_span.start_line.should eq(1)
    diagnostic.primary_span.start_column.should eq(1)
  end

  it "uses a default span for an out-of-range source location" do
    program = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("1\n")
    ).parse_program
    expander = Adamas::Compiler::Semantic::MacroExpander.new(program, program.arena)

    expander.__test_emit_error("out of range", Adamas::Compiler::Frontend::ExprId.new(1_000_000))

    expander.diagnostics.size.should eq(1)
    expander.diagnostics.first.primary_span.start_line.should eq(1)
  end

  it "returns an invalid expression for an empty reparse result" do
    program = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("1\n")
    ).parse_program
    expander = Adamas::Compiler::Semantic::MacroExpander.new(program, program.arena)
    location = program.roots.first

    result = expander.reparse_output("", location)

    result.invalid?.should be_true
    expander.diagnostics.should be_empty
  end

  it "returns an invalid expression for a whitespace-only reparse result" do
    program = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("1\n")
    ).parse_program
    expander = Adamas::Compiler::Semantic::MacroExpander.new(program, program.arena)
    location = program.roots.first

    result = expander.reparse_output(" \n\t", location)

    result.invalid?.should be_true
    expander.diagnostics.should be_empty
  end
end
