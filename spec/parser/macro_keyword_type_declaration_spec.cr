require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"

include Adamas::Compiler

describe "source-owned keyword TypeDeclaration macro arguments" do
  it "uses declaration grammar for keyword names" do
    {"next : Int32" => "next", "break : ::Pointer(self)" => "break", "return : Int32 = 65" => "return"}.each do |source, name|
      parser = Frontend::Parser.new(Frontend::Lexer.new(source))
      id = parser.parse_macro_keyword_type_declaration_argument(name.to_slice).not_nil!
      id.invalid?.should be_false
      parser.diagnostics.should be_empty
      node = parser.arena[id].as(Frontend::TypeDeclarationNode)
      String.new(node.name).should eq(name)
    end
  end

  it "keeps structured source-owned type forms and initializer AST" do
    ["Int32 | Nil", "Array({String, Int32})", "-> Int32", "(Int32, String) -> Bool", "typeof(value)", "::Pointer(self)", "Int32?", "StaticArray(UInt8, 4)"].each do |type|
      parser = Frontend::Parser.new(Frontend::Lexer.new("next : #{type} = initializer(65)"))
      id = parser.parse_macro_keyword_type_declaration_argument("next".to_slice).not_nil!
      id.invalid?.should be_false, type
      parser.diagnostics.should be_empty
      node = parser.arena[id].as(Frontend::TypeDeclarationNode)
      node.value.should_not be_nil
      String.new(node.declared_type).strip.should eq(type)
    end
  end

  ["next", "next :", "break : Int32", "next : Int32; other : Int32", "next : Int32 junk"].each do |source|
    it "rejects malformed or mismatched input #{source.inspect}" do
      parser = Frontend::Parser.new(Frontend::Lexer.new(source))
      parser.parse_macro_keyword_type_declaration_argument("next".to_slice).not_nil!.invalid?.should be_true
    end
  end

  it "leaves ordinary identifier declarations on the generic parser path" do
    parser = Frontend::Parser.new(Frontend::Lexer.new("ordinary : Int32"))
    parser.parse_macro_keyword_type_declaration_argument("ordinary".to_slice).should be_nil
    parser.diagnostics.should be_empty
  end
end
