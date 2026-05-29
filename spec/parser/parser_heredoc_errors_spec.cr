require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "heredoc error handling" do
    it "reports indent error" do
      source = "<<-HERE\n One\n  #{1}\n  HERE"
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(source, diagnostics: [] of Adamas::Compiler::Frontend::Diagnostic)
      )
      parser.parse_program

      parser.diagnostics.should_not be_empty
    end

    it "reports heredoc inside interpolation" do
      source = %q("#{<<-HERE}\nHERE")
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(source, diagnostics: [] of Adamas::Compiler::Frontend::Diagnostic)
      )
      parser.parse_program

      parser.diagnostics.should_not be_empty
    end

    it "reports missing terminator" do
      source = "<<-FOO\n1\nFOO.bar"
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(source)
      )
      parser.parse_program

      parser.diagnostics.should_not be_empty
    end

    it "reports unexpected EOF" do
      source = "<<-HEREDOC"
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(source)
      )
      parser.parse_program

      parser.diagnostics.should_not be_empty
    end
  end
end
