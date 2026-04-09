require "spec"

require "../../src/compiler/frontend/parser"

describe "CrystalV2::Compiler::Frontend::Parser" do
  describe "case/in predicate patterns" do
    it "parses dot predicates as implicit zero-arg calls" do
      source = <<-CRYSTAL
        case state
        in .delivered?
          1
        end
      CRYSTAL

      parser = CrystalV2::Compiler::Frontend::Parser.new(
        CrystalV2::Compiler::Frontend::Lexer.new(source)
      )
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)

      arena = program.arena
      case_node = arena[program.roots.first].as(CrystalV2::Compiler::Frontend::CaseNode)
      branch = case_node.in_branches.not_nil!.first
      pattern = arena[branch.conditions.first].as(CrystalV2::Compiler::Frontend::CallNode)
      callee = arena[pattern.callee].as(CrystalV2::Compiler::Frontend::MemberAccessNode)
      receiver = arena[callee.object]

      receiver.should be_a(CrystalV2::Compiler::Frontend::ImplicitObjNode)
      String.new(callee.member).should eq("delivered?")
      pattern.args.should be_empty
    end
  end
end
