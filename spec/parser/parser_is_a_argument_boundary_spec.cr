require "spec"
require "../../src/compiler/frontend/parser"

describe "is_a? type argument boundary" do
  [
    "value.is_a?(Int32, trick: true)",
    "value.is_a?(Int32, Int64)",
    "value.is_a?(Int32,)",
    "value.is_a?(Int32 trick)",
    "is_a?(Int32, trick: true)",
    "is_a?(Int32, Int64)",
    "is_a?(Int32,)",
    "is_a?(Int32 trick)",
  ].each do |source|
    it "rejects extra tokens after the type in #{source}" do
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      parser.parse_program
      parser.diagnostics.should_not be_empty
      parser.diagnostics.any? { |diagnostic| diagnostic.message.includes?("expecting token: )") }.should be_true
    end
  end

  ["value.is_a?()", "is_a?()"].each do |source|
    it "rejects a missing type argument in #{source}" do
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      parser.parse_program
      parser.diagnostics.should_not be_empty
    end
  end

  it "keeps comments out of the selected type spelling" do
    source = "value.is_a?(Int32 # guard type\n)"
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    check = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::IsANode)
    String.new(check.target_type).should eq("Int32")
  end

  [
    "value.is_a?(Int32)",
    "value.is_a?(\n  Int32\n)",
    "is_a?(\n  Int32\n)",
    "value.is_a?(Int32 # guard type\n)",
    "value.is_a?(Int32 |\n Nil\n)",
    "is_a?(Int32)",
    "value.is_a?(Tuple(Int32, Int64))",
    "value.is_a?({Int32, Int64})",
    "value.is_a?(Int32 | Nil)",
    "value.is_a?(Proc(Int32, Int64))",
    "value.is_a?(Int32, Int64 -> Bool)",
    "value.is_a?(Int32,\n  Int64 -> Bool)",
    "is_a?(Int32, # proc input\n  Int64 -> Bool)",
    "value.is_a?(Int32 -> Bool)",
    "value.is_a?(-> Bool)",
    "value.is_a?(::Root::Child)",
    "value.is_a?(Int32?)",
    "value.is_a?(typeof(value))",
    "value.is_a?({{ type }})",
    "value.is_a?({{ type }} | Nil)",
    "value.is_a?(Tuple({{ type }}, Int32))",
    "value.is_a?(GuardChild.class)",
    "value.is_a? Int32",
    "value.is_a?(Int32) && other.is_a?(Int64)",
  ].each do |source|
    it "preserves valid nested type syntax in #{source}" do
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program
      parser.diagnostics.should be_empty
      program.roots.should_not be_empty
    end
  end
end
