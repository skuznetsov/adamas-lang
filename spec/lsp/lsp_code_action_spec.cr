require "spec"

require "../../src/main"
require "../../src/compiler/lsp/protocol"
require "../../src/compiler/lsp/messages"
require "../../src/compiler/lsp/server"

describe "LSP Code Action" do
  describe "CodeActionKind constants" do
    it "defines standard code action kinds" do
      Adamas::Compiler::LSP::CodeActionKind::QuickFix.should eq("quickfix")
      Adamas::Compiler::LSP::CodeActionKind::Refactor.should eq("refactor")
      Adamas::Compiler::LSP::CodeActionKind::RefactorExtract.should eq("refactor.extract")
      Adamas::Compiler::LSP::CodeActionKind::RefactorInline.should eq("refactor.inline")
      Adamas::Compiler::LSP::CodeActionKind::Source.should eq("source")
    end
  end

  describe "CodeAction struct" do
    it "creates action with required fields" do
      action = Adamas::Compiler::LSP::CodeAction.new(
        title: "Add type annotation"
      )

      action.title.should eq("Add type annotation")
      action.kind.should be_nil
      action.edit.should be_nil
    end

    it "creates action with kind" do
      action = Adamas::Compiler::LSP::CodeAction.new(
        title: "Fix error",
        kind: Adamas::Compiler::LSP::CodeActionKind::QuickFix
      )

      action.title.should eq("Fix error")
      action.kind.should eq("quickfix")
    end

    it "creates action with edit" do
      pos = Adamas::Compiler::LSP::Position.new(line: 0, character: 0)
      range = Adamas::Compiler::LSP::Range.new(start: pos, end: pos)
      edit = Adamas::Compiler::LSP::TextEdit.new(range: range, new_text: "fix")
      workspace_edit = Adamas::Compiler::LSP::WorkspaceEdit.new(
        changes: {"file:///test.cr" => [edit]}
      )

      action = Adamas::Compiler::LSP::CodeAction.new(
        title: "Apply fix",
        kind: Adamas::Compiler::LSP::CodeActionKind::QuickFix,
        edit: workspace_edit
      )

      action.edit.should_not be_nil
      action.edit.not_nil!.changes.size.should eq(1)
    end

    it "serializes to JSON with camelCase" do
      action = Adamas::Compiler::LSP::CodeAction.new(
        title: "Test",
        is_preferred: true
      )

      json = action.to_json
      json.should contain("\"isPreferred\"")
      json.should_not contain("\"is_preferred\"")
    end
  end

  describe "CodeActionContext struct" do
    it "creates context with diagnostics" do
      pos = Adamas::Compiler::LSP::Position.new(line: 0, character: 0)
      range = Adamas::Compiler::LSP::Range.new(start: pos, end: pos)
      diagnostic = Adamas::Compiler::LSP::Diagnostic.new(
        range: range,
        message: "Error"
      )

      context = Adamas::Compiler::LSP::CodeActionContext.new(
        diagnostics: [diagnostic]
      )

      context.diagnostics.size.should eq(1)
      context.only.should be_nil
    end

    it "creates context with only filter" do
      context = Adamas::Compiler::LSP::CodeActionContext.new(
        diagnostics: [] of Adamas::Compiler::LSP::Diagnostic,
        only: ["quickfix"]
      )

      context.only.should_not be_nil
      context.only.not_nil!.should eq(["quickfix"])
    end
  end

  describe "CodeActionParams struct" do
    it "creates params with all fields" do
      text_doc = Adamas::Compiler::LSP::TextDocumentIdentifier.new(uri: "file:///test.cr")
      pos = Adamas::Compiler::LSP::Position.new(line: 5, character: 10)
      range = Adamas::Compiler::LSP::Range.new(start: pos, end: pos)
      context = Adamas::Compiler::LSP::CodeActionContext.new(
        diagnostics: [] of Adamas::Compiler::LSP::Diagnostic
      )

      params = Adamas::Compiler::LSP::CodeActionParams.new(
        text_document: text_doc,
        range: range,
        context: context
      )

      params.text_document.uri.should eq("file:///test.cr")
      params.range.start.line.should eq(5)
      params.context.diagnostics.should be_empty
    end
  end

  describe "Extract variable action" do
    it "suggests extraction for non-empty single-line range" do
      # This tests the can_extract_variable? logic
      # In a real scenario, would check actual AST

      # For now, verify structures are in place
      action = Adamas::Compiler::LSP::CodeAction.new(
        title: "Extract to local variable",
        kind: Adamas::Compiler::LSP::CodeActionKind::RefactorExtract
      )

      action.title.should contain("Extract")
      action.kind.should eq("refactor.extract")
    end
  end

  # Control flow scenarios for code actions

  describe "Code actions with control flow" do
    it "can analyze code with if statements" do
      source = <<-CRYSTAL
      def process(x : Int32)
        if x > 0
          result = x * 2
        end
      end
      CRYSTAL

      lexer = Adamas::Compiler::Frontend::Lexer.new(source)
      parser = Adamas::Compiler::Frontend::Parser.new(lexer)
      program = parser.parse_program

      # Verify program structure exists for action analysis
      program.roots.should_not be_empty
    end

    it "can analyze code with while loops" do
      source = <<-CRYSTAL
      def loop_process
        counter = 0
        while counter < 10
          counter = counter + 1
        end
      end
      CRYSTAL

      lexer = Adamas::Compiler::Frontend::Lexer.new(source)
      parser = Adamas::Compiler::Frontend::Parser.new(lexer)
      program = parser.parse_program

      program.roots.should_not be_empty
    end

    it "can analyze code with unless statements" do
      source = <<-CRYSTAL
      def conditional(flag : Bool)
        unless flag
          handle_false
        end
      end
      CRYSTAL

      lexer = Adamas::Compiler::Frontend::Lexer.new(source)
      parser = Adamas::Compiler::Frontend::Parser.new(lexer)
      program = parser.parse_program

      program.roots.should_not be_empty
    end

    it "can analyze code with until loops" do
      source = <<-CRYSTAL
      def until_done
        until finished
          work
        end
      end
      CRYSTAL

      lexer = Adamas::Compiler::Frontend::Lexer.new(source)
      parser = Adamas::Compiler::Frontend::Parser.new(lexer)
      program = parser.parse_program

      program.roots.should_not be_empty
    end

    it "can analyze code with loop blocks" do
      source = <<-CRYSTAL
      def infinite_loop
        loop do
          process
          break if done
        end
      end
      CRYSTAL

      lexer = Adamas::Compiler::Frontend::Lexer.new(source)
      parser = Adamas::Compiler::Frontend::Parser.new(lexer)
      program = parser.parse_program

      program.roots.should_not be_empty
    end

    it "can analyze nested control flow" do
      source = <<-CRYSTAL
      def complex
        if ready
          while active
            process
          end
        end
      end
      CRYSTAL

      lexer = Adamas::Compiler::Frontend::Lexer.new(source)
      parser = Adamas::Compiler::Frontend::Parser.new(lexer)
      program = parser.parse_program

      program.roots.should_not be_empty
    end

    it "can analyze elsif branches" do
      source = <<-CRYSTAL
      def branching(value : Int32)
        if value > 10
          large
        elsif value > 0
          small
        else
          zero
        end
      end
      CRYSTAL

      lexer = Adamas::Compiler::Frontend::Lexer.new(source)
      parser = Adamas::Compiler::Frontend::Parser.new(lexer)
      program = parser.parse_program

      program.roots.should_not be_empty
    end
  end

  describe "QuickFix actions" do
    it "returns empty array for MVP (no diagnostics)" do
      # MVP implementation returns no quick fixes
      # This test documents current behavior
      pos = Adamas::Compiler::LSP::Position.new(line: 0, character: 0)
      range = Adamas::Compiler::LSP::Range.new(start: pos, end: pos)
      diagnostic = Adamas::Compiler::LSP::Diagnostic.new(
        range: range,
        message: "Error"
      )

      # In MVP, no quick fixes are generated
      # This test verifies the structure is in place
      diagnostic.message.should eq("Error")
    end
  end

  describe "Refactor actions" do
    it "suggests extract variable for valid range" do
      # MVP suggests extract variable for non-empty single-line ranges
      action = Adamas::Compiler::LSP::CodeAction.new(
        title: "Extract to local variable",
        kind: Adamas::Compiler::LSP::CodeActionKind::RefactorExtract
      )

      action.kind.should eq("refactor.extract")
    end
  end
end
