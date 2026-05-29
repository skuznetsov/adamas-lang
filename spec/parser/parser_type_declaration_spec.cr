require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 66: Type Declaration (PRODUCTION-READY)" do
    it "parses simple type declaration" do
      source = "x : Int32"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      type_decl = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(type_decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)

      String.new(Adamas::Compiler::Frontend.node_type_decl_name(type_decl).not_nil!).should eq("x")
      String.new(Adamas::Compiler::Frontend.node_type_decl_var(type_decl).not_nil!).should eq("x")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(type_decl).not_nil!).should eq("Int32")
    end

    it "parses type declaration with String type" do
      source = "name : String"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      type_decl = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(type_decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)

      String.new(Adamas::Compiler::Frontend.node_type_decl_name(type_decl).not_nil!).should eq("name")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(type_decl).not_nil!).should eq("String")
    end

    it "parses type declaration with custom type" do
      source = "user : User"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      type_decl = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(type_decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)

      String.new(Adamas::Compiler::Frontend.node_type_decl_name(type_decl).not_nil!).should eq("user")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(type_decl).not_nil!).should eq("User")
    end

    it "parses multiple type declarations" do
      source = <<-CRYSTAL
      x : Int32
      y : String
      z : Bool
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(3)
      arena = program.arena

      # First declaration
      decl1 = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(decl1).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)
      String.new(Adamas::Compiler::Frontend.node_type_decl_name(decl1).not_nil!).should eq("x")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(decl1).not_nil!).should eq("Int32")

      # Second declaration
      decl2 = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_kind(decl2).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)
      String.new(Adamas::Compiler::Frontend.node_type_decl_name(decl2).not_nil!).should eq("y")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(decl2).not_nil!).should eq("String")

      # Third declaration
      decl3 = arena[program.roots[2]]
      Adamas::Compiler::Frontend.node_kind(decl3).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)
      String.new(Adamas::Compiler::Frontend.node_type_decl_name(decl3).not_nil!).should eq("z")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(decl3).not_nil!).should eq("Bool")
    end

    it "parses type declaration followed by assignment" do
      source = <<-CRYSTAL
      x : Int32
      x = 5
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(2)
      arena = program.arena

      # First: type declaration
      decl = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)

      # Second: assignment
      assign = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_kind(assign).should eq(Adamas::Compiler::Frontend::NodeKind::Assign)
    end

    it "parses type declaration inside class" do
      source = <<-CRYSTAL
      class Foo
        x : Int32
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      class_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(class_node).should eq(Adamas::Compiler::Frontend::NodeKind::Class)

      body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
      body.size.should eq(1)

      decl = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)
      String.new(Adamas::Compiler::Frontend.node_type_decl_name(decl).not_nil!).should eq("x")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(decl).not_nil!).should eq("Int32")
    end

    it "parses type declaration inside method" do
      source = <<-CRYSTAL
      def foo
        x : Int32
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      method_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(method_node).should eq(Adamas::Compiler::Frontend::NodeKind::Def)

      body = Adamas::Compiler::Frontend.node_def_body(method_node).not_nil!
      body.size.should eq(1)

      decl = arena[body[0]]
      Adamas::Compiler::Frontend.node_kind(decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)
    end

    it "parses type declaration with spaces" do
      source = "x    :    Int32"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      type_decl = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(type_decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)
      String.new(Adamas::Compiler::Frontend.node_type_decl_name(type_decl).not_nil!).should eq("x")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(type_decl).not_nil!).should eq("Int32")
    end

    it "parses type declaration with Array type" do
      source = "items : Array"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      type_decl = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(type_decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)
      String.new(Adamas::Compiler::Frontend.node_type_decl_name(type_decl).not_nil!).should eq("items")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(type_decl).not_nil!).should eq("Array")
    end

    it "parses type declaration with Hash type" do
      source = "data : Hash"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      type_decl = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(type_decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)
      String.new(Adamas::Compiler::Frontend.node_type_decl_name(type_decl).not_nil!).should eq("data")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(type_decl).not_nil!).should eq("Hash")
    end

    it "parses type declaration with tuple type" do
      source = "pair : {Int32, String}"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      type_decl = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(type_decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)
      String.new(Adamas::Compiler::Frontend.node_type_decl_name(type_decl).not_nil!).should eq("pair")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(type_decl).not_nil!).should eq("{Int32, String}")
    end

    it "parses type declaration with typeof annotation" do
      source = "value : typeof(foo.bar)"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      type_decl = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(type_decl).should eq(Adamas::Compiler::Frontend::NodeKind::TypeDeclaration)
      String.new(Adamas::Compiler::Frontend.node_type_decl_name(type_decl).not_nil!).should eq("value")
      String.new(Adamas::Compiler::Frontend.node_type_decl_type(type_decl).not_nil!).should eq("typeof(foo.bar)")
    end

    it "parses method with tuple return type annotation" do
      source = <<-CRYSTAL
      def pair(x, y) : {Int32, String}
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      method_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(method_node).should eq(Adamas::Compiler::Frontend::NodeKind::Def)

      return_type = Adamas::Compiler::Frontend.node_def_return_type(method_node).not_nil!
      String.new(return_type).should eq("{Int32, String}")
    end
  end
end
