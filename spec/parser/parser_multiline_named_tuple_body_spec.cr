require "spec"
require "../../src/compiler/frontend/parser"

describe "Multiline NamedTuple method bodies" do
  it "retains a tuple with shorthand block calls as the method body" do
    source = <<-CRYSTAL
      class User
        def user_details
          {
            name:              @name,
            password_hash:     @password,
            hashing_algorithm: @password.try &.hash_algorithm,
            tags:              @tags.map(&.to_s.downcase).join(","),
          }
        end
      end
      CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    arena = program.arena
    owner = arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
    method = arena[owner.body.not_nil!.first].as(Adamas::Compiler::Frontend::DefNode)
    parser.diagnostics.map(&.message).should be_empty
    method.body.not_nil!.size.should eq(1)
    tuple = arena[method.body.not_nil!.first].as(Adamas::Compiler::Frontend::NamedTupleLiteralNode)
    tuple.entries.size.should eq(4)
  end
end

["{value: obj.try &.value}",
 "{value: obj.try &.value, after: 7}",
 "{value: obj.try(&.value), after: 7}",
 "{value: obj.try &callback, after: 7}",
 "{value: obj.try &@callback, after: 7}",
 "{value: bare_try &callback, after: 7}",
 "{value: obj.select &.value, after: 7}",
 "{value: bare_try &.value, after: 7}",
 "{value: obj.try &.value,}",
 "{value: obj.try &.value,\n}",
 "{value: obj.map(&.first.second).join(\",\"), after: 7}"]
.each do |source|
  describe "Block argument collection boundary" do
    it source do
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program
      parser.diagnostics.map(&.message).should be_empty
      program.roots.size.should eq(1)
      tuple = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::NamedTupleLiteralNode)
      tuple.entries.size.should eq(source.includes?("after:") ? 2 : 1)
    end
  end
end

[
  "[obj.try &.value, 7]",
  "{obj.try &.value, 7}",
  "outer(obj.try &.value, 7)",
].each do |source|
  describe "Block argument enclosing comma" do
    it source do
      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program
      parser.diagnostics.map(&.message).should be_empty
      program.roots.size.should eq(1)
      outer = program.arena[program.roots.first]
      items = case outer
              when Adamas::Compiler::Frontend::ArrayLiteralNode, Adamas::Compiler::Frontend::TupleLiteralNode
                outer.elements
              when Adamas::Compiler::Frontend::CallNode
                outer.args
              else
                raise "expected enclosing collection or call"
              end
      items.size.should eq(2)
      program.arena[items.first].should be_a(Adamas::Compiler::Frontend::CallNode)
      program.arena[items.last].should be_a(Adamas::Compiler::Frontend::NumberNode)
    end
  end
end

describe "Ordinary no-parentheses argument lists" do
  it "keeps positional commas after a binary ampersand expression" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new("obj.call 1 & 3, 7"))
    program = parser.parse_program
    parser.diagnostics.map(&.message).should be_empty
    call = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::CallNode)
    call.args.size.should eq(2)
    program.arena[call.args.first].should be_a(Adamas::Compiler::Frontend::BinaryNode)
  end
end
