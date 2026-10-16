require "./semantic_cli_helpers"
require "../src/compiler/cli"

include SemanticCliSpecHelpers

private def generated_root_hir(source : String) : String
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

describe "CLI generated root ownership" do
  it "collects conditional runtime roots and declarations in their parser arena" do
    hir = generated_root_hir(<<-CRYSTAL)
      {% if true %}
        GENERATED_ROOT = 65
        def generated_root_value
          GENERATED_ROOT
        end
        puts generated_root_value
      {% end %}
      puts 66
      CRYSTAL
    hir.should contain("func @generated_root_value")
    hir.should contain("call generated_root_value")
    hir.should contain("literal 65 : Int32")
    hir.should contain("literal 66 : Int32")
  end

  it "collects begin and for runtime roots without resolving them in the source arena" do
    hir = generated_root_hir(<<-CRYSTAL)
      {% begin %}
        puts 71
      {% end %}
      {% for value in %w(73 79) %}
        puts {{value.id}}
      {% end %}
      puts 83
      CRYSTAL
    {71, 73, 79, 83}.each do |value|
      hir.should contain("literal #{value} : Int32")
    end
  end

  it "keeps generated class methods inside their declared owner" do
    hir = generated_root_hir(<<-CRYSTAL)
      {% if true %}
        class GeneratedRootOwner
          def nested_value
            89
          end
        end
      {% end %}
      GeneratedRootOwner.new.nested_value
      CRYSTAL
    hir.should contain("func @GeneratedRootOwner#nested_value")
    hir.should_not contain("func @nested_value(")
    hir.should contain("literal 89 : Int32")
  end

  it "rejects parser recovery roots from malformed generated declarations" do
    with_temp_shadow_project({"main.cr" => <<-CRYSTAL}) do |dir|
      {% for name in %w(broken) %}
        def {{name.id}}(
          42
        end
      {% end %}
      CRYSTAL
      errors = IO::Memory.new
      status = Adamas::Compiler::CLI.new([
        File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir",
        "--no-link", "--no-ast-cache", "--no-llvm-cache", "-o", File.join(dir, "main"),
      ]).run(out_io: IO::Memory.new, err_io: errors)
      status.should eq(1)
      errors.to_s.should contain("invalid generated macro expansion")
    end
  end
end
