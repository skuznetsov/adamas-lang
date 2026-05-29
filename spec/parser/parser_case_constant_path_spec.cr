require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "case with constant paths" do
    it "parses chained const paths in when branches" do
      source = <<-CRYSTAL
        severity = case diag.level
        when Semantic::DiagnosticLevel::Error
          DiagnosticSeverity::Error.value
        when Semantic::DiagnosticLevel::Warning
          DiagnosticSeverity::Warning.value
        else
          DiagnosticSeverity::Information.value
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(source)
      )
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)

      arena = program.arena
      assign_node = arena[program.roots.first].as(Adamas::Compiler::Frontend::AssignNode)
      Adamas::Compiler::Frontend.node_kind(assign_node).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)

      case_id = Adamas::Compiler::Frontend.node_assign_value(assign_node)
      case_node = arena[case_id].as(Adamas::Compiler::Frontend::CaseNode)
      Adamas::Compiler::Frontend.node_kind(case_node).should eq(Adamas::Compiler::Frontend::NodeKind::Case)

      whens = Adamas::Compiler::Frontend.node_when_branches(case_node)
      whens.size.should eq(2)

      else_branch = Adamas::Compiler::Frontend.node_case_else(case_node)
      else_branch.should_not be_nil
      else_branch.not_nil!.size.should eq(1)
    end
  end
end
