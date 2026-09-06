require "spec"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/macro_expander"

private def enum_reflection_owner(name : String, members : Hash(String, Int64), flags : Bool = false)
  scope = Adamas::Compiler::Semantic::SymbolTable.new
  owner = Adamas::Compiler::Semantic::ClassSymbol.new(name, Adamas::Compiler::Frontend::ExprId.new(-1), scope: scope, class_scope: scope, is_struct: true)
  owner.enum_members = members
  if flags
    owner.add_annotation(Adamas::Compiler::Semantic::AnnotationInfo.new("Flags", [] of Adamas::Compiler::Frontend::ExprId, {} of String => Adamas::Compiler::Frontend::ExprId))
  end
  owner
end

private def enum_reflection_text(source : String, owner : Adamas::Compiler::Semantic::ClassSymbol)
  program = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source)).parse_program
  expander = Adamas::Compiler::Semantic::MacroExpander.new(program, program.arena, Set(String).new)
  variables = {"member" => Adamas::Compiler::Semantic::MacroIdValue.new("Seven").as(Adamas::Compiler::Semantic::MacroValue)}
  expander.expand_expression(program.roots.first, variables: variables, owner_type: owner)
end

describe "enum reflection across HIR macro owners" do
  it "preserves numeric values, including zero and negative members" do
    [0_i64, 7_i64, -9_i64].each do |value|
      owner = enum_reflection_owner("Kind", {"Seven" => value})
      enum_reflection_text("@type.constant(member)", owner).should eq(value.to_s)
    end
  end

  it "keeps constants from sibling owners separate" do
    a = enum_reflection_owner("Left::Kind", {"Seven" => 7_i64})
    b = enum_reflection_owner("Right::Kind", {"Seven" => 17_i64})
    enum_reflection_text("@type.constant(member)", a).should eq("7")
    enum_reflection_text("@type.constant(member)", b).should eq("17")
    enum_reflection_text("@type.constant(member)", a).should eq("7")
  end

  it "keeps missing constant lookup empty" do
    owner = enum_reflection_owner("Kind", {"Other" => 1_i64})
    enum_reflection_text("@type.constant(member)", owner).should eq("")
  end

  it "dereferences reflection receivers for names and annotations" do
    plain = enum_reflection_owner("Plain", {"Seven" => 7_i64})
    flags = enum_reflection_owner("Bits", {"Seven" => 7_i64}, true)
    enum_reflection_text("@type.name(generic_args: false)", plain).should eq("Plain")
    enum_reflection_text("@type.annotation(Flags)", plain).should eq("")
    enum_reflection_text("@type.annotation(Flags)", flags).should eq("@[Flags]")
  end

  it "preserves annotation truthiness in a macro conditional" do
    source = "{% if @type.annotation(Flags) %}11{% else %}22{% end %}"
    program = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source)).parse_program
    expander = Adamas::Compiler::Semantic::MacroExpander.new(program, program.arena, Set(String).new)
    plain = enum_reflection_owner("Plain", {"Seven" => 7_i64})
    flags = enum_reflection_owner("Bits", {"Seven" => 7_i64}, true)
    expander.expand_top_level_text(program.roots.first, owner_type: plain).strip.should eq("22")
    expander.expand_top_level_text(program.roots.first, owner_type: flags).strip.should eq("11")
  end
end
