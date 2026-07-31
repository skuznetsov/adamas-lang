require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/context"
require "../../src/compiler/semantic/collectors/symbol_collector"
require "../../src/compiler/semantic/symbol"

module AccessorExpansionSpecAliases
  alias Frontend = Adamas::Compiler::Frontend
  alias Semantic = Adamas::Compiler::Semantic
end

include AccessorExpansionSpecAliases

describe "Phase 87B-1: Accessor Macro Expansion" do
  describe "getter expansion" do
    it "expands getter to method definition" do
      source = <<-CR
        class Person
          getter name : String
        end
      CR

      lexer = Frontend::Lexer.new(source)
      parser = Frontend::Parser.new(lexer)
      program = parser.parse_program

      context = Semantic::Context.new(Semantic::SymbolTable.new)
      collector = Semantic::SymbolCollector.new(program, context)
      collector.collect

      # Verify class exists
      person_symbol = context.symbol_table.lookup("Person")
      person_symbol.should_not be_nil
      person_symbol.should be_a(Semantic::ClassSymbol)

      # Verify getter expanded to method "name"
      person_class = person_symbol.as(Semantic::ClassSymbol)
      name_method = person_class.scope.lookup("name")
      name_method.should_not be_nil
      name_method.should be_a(Semantic::MethodSymbol)

      # Verify method signature
      method = name_method.as(Semantic::MethodSymbol)
      method.return_annotation.should eq("String")
      method.params.should be_empty
    end

    it "expands getter without type annotation" do
      source = <<-CR
        class Person
          getter name
        end
      CR

      lexer = Frontend::Lexer.new(source)
      parser = Frontend::Parser.new(lexer)
      program = parser.parse_program

      context = Semantic::Context.new(Semantic::SymbolTable.new)
      collector = Semantic::SymbolCollector.new(program, context)
      collector.collect

      person_symbol = context.symbol_table.lookup("Person")
      person_class = person_symbol.as(Semantic::ClassSymbol)
      name_method = person_class.scope.lookup("name")

      name_method.should_not be_nil
      name_method.should be_a(Semantic::MethodSymbol)

      method = name_method.as(Semantic::MethodSymbol)
      method.return_annotation.should be_nil
    end

    it "expands multiple getters" do
      source = <<-CR
        class Person
          getter name, age, email
        end
      CR

      lexer = Frontend::Lexer.new(source)
      parser = Frontend::Parser.new(lexer)
      program = parser.parse_program

      context = Semantic::Context.new(Semantic::SymbolTable.new)
      collector = Semantic::SymbolCollector.new(program, context)
      collector.collect

      person_symbol = context.symbol_table.lookup("Person")
      person_class = person_symbol.as(Semantic::ClassSymbol)

      # Verify all three methods created
      person_class.scope.lookup("name").should be_a(Semantic::MethodSymbol)
      person_class.scope.lookup("age").should be_a(Semantic::MethodSymbol)
      person_class.scope.lookup("email").should be_a(Semantic::MethodSymbol)
    end

    it "records accessor storage and annotation metadata through the base-node collector path" do
      source = <<-CR
        annotation Stored
        end

        class Config
          @[Stored]
          getter name : String = "default"
        end
      CR

      lexer = Frontend::Lexer.new(source)
      parser = Frontend::Parser.new(lexer)
      program = parser.parse_program

      context = Semantic::Context.new(Semantic::SymbolTable.new)
      collector = Semantic::SymbolCollector.new(program, context)
      collector.collect

      config = context.symbol_table.lookup("Config").as(Semantic::ClassSymbol)
      info = config.get_instance_var_info("name")
      info.should_not be_nil
      info.not_nil!.type_annotation.should eq("String")
      info.not_nil!.has_default?.should be_true
      info.not_nil!.default_value.should_not be_nil

      annotations = config.ivar_annotations["name"]?
      annotations.should_not be_nil
      annotations.not_nil!.map(&.full_name).should contain("Stored")
    end
  end

  describe "setter expansion" do
    it "expands setter to method definition with parameter" do
      source = <<-CR
        class Person
          setter name : String
        end
      CR

      lexer = Frontend::Lexer.new(source)
      parser = Frontend::Parser.new(lexer)
      program = parser.parse_program

      context = Semantic::Context.new(Semantic::SymbolTable.new)
      collector = Semantic::SymbolCollector.new(program, context)
      collector.collect

      person_symbol = context.symbol_table.lookup("Person")
      person_class = person_symbol.as(Semantic::ClassSymbol)

      # Verify setter expanded to method "name="
      setter_method = person_class.scope.lookup("name=")
      setter_method.should_not be_nil
      setter_method.should be_a(Semantic::MethodSymbol)

      # Verify method signature
      method = setter_method.as(Semantic::MethodSymbol)
      method.return_annotation.should eq("String")
      method.params.size.should eq(1)
      method.params[0].name.should eq("value".to_slice)
    end
  end

  describe "property expansion" do
    it "expands property to both getter and setter" do
      source = <<-CR
        class Person
          property name : String
        end
      CR

      lexer = Frontend::Lexer.new(source)
      parser = Frontend::Parser.new(lexer)
      program = parser.parse_program

      context = Semantic::Context.new(Semantic::SymbolTable.new)
      collector = Semantic::SymbolCollector.new(program, context)
      collector.collect

      person_symbol = context.symbol_table.lookup("Person")
      person_class = person_symbol.as(Semantic::ClassSymbol)

      # Verify getter created
      getter_method = person_class.scope.lookup("name")
      getter_method.should_not be_nil
      getter_method.should be_a(Semantic::MethodSymbol)
      getter_method.as(Semantic::MethodSymbol).params.should be_empty

      # Verify setter created
      setter_method = person_class.scope.lookup("name=")
      setter_method.should_not be_nil
      setter_method.should be_a(Semantic::MethodSymbol)
      setter_method.as(Semantic::MethodSymbol).params.size.should eq(1)
    end
  end

  describe "mixed accessors" do
    it "handles getter, setter, and property together" do
      source = <<-CR
        class Person
          getter name : String
          setter age : Int32
          property email : String
        end
      CR

      lexer = Frontend::Lexer.new(source)
      parser = Frontend::Parser.new(lexer)
      program = parser.parse_program

      context = Semantic::Context.new(Semantic::SymbolTable.new)
      collector = Semantic::SymbolCollector.new(program, context)
      collector.collect

      person_symbol = context.symbol_table.lookup("Person")
      person_class = person_symbol.as(Semantic::ClassSymbol)

      # Verify getter "name"
      person_class.scope.lookup("name").should be_a(Semantic::MethodSymbol)

      # Verify setter "age="
      person_class.scope.lookup("age=").should be_a(Semantic::MethodSymbol)

      # Verify property "email" + "email="
      person_class.scope.lookup("email").should be_a(Semantic::MethodSymbol)
      person_class.scope.lookup("email=").should be_a(Semantic::MethodSymbol)
    end
  end
end
