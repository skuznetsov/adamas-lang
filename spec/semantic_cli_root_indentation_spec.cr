require "./semantic_cli_helpers"
require "../src/compiler/cli"

include SemanticCliSpecHelpers

private def root_indentation_hir(source : String) : String
  with_temp_shadow_project({"main.cr" => source}) do |dir|
    target = File.join(dir, "main")
    errors = IO::Memory.new
    status = Adamas::Compiler::CLI.new([
      File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir",
      "--no-link", "--no-ast-cache", "--no-llvm-cache", "-o", target,
    ]).run(out_io: IO::Memory.new, err_io: errors)
    status.should eq(0), errors.to_s
    File.read("#{target}.hir")
  end
end

describe "CLI parser-owned root collection" do
  {"" => "column zero", "    " => "spaces", "\t" => "tabs"}.each do |indent, name|
    it "collects root constants, assignments, defs and calls with #{name}" do
      source = [
        "ROOT_VALUE = 40",
        "assigned = ROOT_VALUE + 2",
        "def root_helper",
        "  ROOT_VALUE + 2",
        "end",
        "puts assigned",
        "puts root_helper",
      ].map { |line| indent + line }.join("\n") + "\n"
      hir = root_indentation_hir(source)
      hir.should contain("func @root_helper")
      hir.should contain("literal 40 : Int32")
      hir.should contain("literal 2 : Int32")
      hir.should contain("call root_helper")
    end
  end

  it "retains parser ownership of nested declarations in an indented class" do
    hir = root_indentation_hir([
      "    class RootIndentationScope",
      "      def nested_value",
      "        97",
      "      end",
      "    end",
      "    def global_root_value",
      "      98",
      "    end",
      "    global_root_value",
      "    RootIndentationScope.new.nested_value",
    ].join("\n") + "\n")
    hir.should contain("func @global_root_value")
    hir.should contain("func @RootIndentationScope#nested_value")
    hir.should_not contain("func @nested_value(")
    hir.should contain("literal 97 : Int32")
    hir.should contain("literal 98 : Int32")
  end
end
