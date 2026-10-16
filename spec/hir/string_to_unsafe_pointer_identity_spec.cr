require "../spec_helper"
require "../semantic_cli_helpers"
require "../../src/compiler/cli"

include SemanticCliSpecHelpers

describe "String raw-byte pointer identity" do
  it "keeps UInt8 element identity through both missing-body call spellings" do
    source = <<-CRYSTAL
      first_pointer = "ж".to_unsafe
      first_string = String.new(first_pointer)
      second_pointer = "ж".to_unsafe()
      second_string = String.new(second_pointer)
      CRYSTAL

    with_temp_shadow_project({"main.cr" => source}) do |dir|
      target = File.join(dir, "main")
      errors = IO::Memory.new
      status = Adamas::Compiler::CLI.new([
        File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir",
        "--no-link", "--no-llvm-cache", "-o", target,
      ]).run(out_io: IO::Memory.new, err_io: errors)
      status.should eq(0), errors.to_s
      hir = File.read("#{target}.hir")
      pointer_type = hir[/type\.(\d+) = Pointer Pointer\(UInt8\)\(7\)/, 1].not_nil!
      calls = hir.lines.select { |line| line.includes?(".String#to_unsafe(") }
      calls.size.should eq(2)
      calls.each { |line| line.rstrip.should end_with(": #{pointer_type}") }
      hir.should contain("call String.new$Pointer(UInt8)(")
      hir.should_not match(/call String\.new\$Pointer\(%/)
    end
  end

  it "keeps an explicitly registered String method return ahead of the missing-body contract" do
    source = <<-CRYSTAL
      class String
        def to_unsafe : Int64
          73_i64
        end
      end
      value = "probe".to_unsafe
      other = "probe".to_unsafe()
      CRYSTAL

    with_temp_shadow_project({"main.cr" => source}) do |dir|
      target = File.join(dir, "main")
      errors = IO::Memory.new
      status = Adamas::Compiler::CLI.new([
        File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir",
        "--no-link", "--no-llvm-cache", "-o", target,
      ]).run(out_io: IO::Memory.new, err_io: errors)
      status.should eq(0), errors.to_s
      hir = File.read("#{target}.hir")
      hir.should contain("func @String#to_unsafe(")
      calls = hir.lines.select { |line| line.includes?(".String#to_unsafe(") }
      calls.size.should eq(2)
      calls.each { |line| line.rstrip.should end_with(": 5") }
      hir.should contain("literal 73 : Int64")
    end
  end

  it "does not infer a byte pointer from an unrelated method name" do
    source = <<-CRYSTAL
      struct UserByteSource
        def to_unsafe : Int64
          79_i64
        end
      end
      value = UserByteSource.new.to_unsafe
      CRYSTAL

    with_temp_shadow_project({"main.cr" => source}) do |dir|
      target = File.join(dir, "main")
      errors = IO::Memory.new
      status = Adamas::Compiler::CLI.new([
        File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir",
        "--no-link", "--no-llvm-cache", "-o", target,
      ]).run(out_io: IO::Memory.new, err_io: errors)
      status.should eq(0), errors.to_s
      hir = File.read("#{target}.hir")
      hir.should match(/call %\d+\.UserByteSource#to_unsafe\(\) : 5/)
    end
  end
end
