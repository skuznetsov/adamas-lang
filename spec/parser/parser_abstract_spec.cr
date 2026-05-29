require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 36: Abstract modifier (PRODUCTION-READY)" do
    it "parses abstract class" do
      source = <<-CRYSTAL
      abstract class Shape
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena
      class_node = arena[program.roots.first]

      Adamas::Compiler::Frontend.node_kind(class_node).should eq(Adamas::Compiler::Frontend::NodeKind::Class)
      String.new(Adamas::Compiler::Frontend.node_class_name(class_node).not_nil!).should eq("Shape")
      Adamas::Compiler::Frontend.node_class_is_abstract(class_node).should be_truthy
    end

    it "parses abstract struct" do
      source = <<-CRYSTAL
      abstract struct Value
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena
      struct_node = arena[program.roots.first]

      Adamas::Compiler::Frontend.node_kind(struct_node).should eq(Adamas::Compiler::Frontend::NodeKind::Struct)
      String.new(Adamas::Compiler::Frontend.node_class_name(struct_node).not_nil!).should eq("Value")
      Adamas::Compiler::Frontend.node_class_is_struct(struct_node).should be_truthy
      Adamas::Compiler::Frontend.node_class_is_abstract(struct_node).should be_truthy
    end

    it "parses abstract method" do
      source = <<-CRYSTAL
      abstract class Shape
        abstract def area : Float64
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena
      class_node = arena[program.roots.first]

      class_body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
      class_body.size.should eq(1)

      method_node = arena[class_body[0]]
      Adamas::Compiler::Frontend.node_kind(method_node).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
      String.new(Adamas::Compiler::Frontend.node_def_name(method_node).not_nil!).should eq("area")
      Adamas::Compiler::Frontend.node_def_is_abstract(method_node).should be_truthy
      Adamas::Compiler::Frontend.node_def_body(method_node).should be_nil
    end

    it "parses multiple abstract methods" do
      source = <<-CRYSTAL
      abstract class Shape
        abstract def area : Float64
        abstract def perimeter : Float64
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena
      class_node = arena[program.roots.first]

      class_body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
      class_body.size.should eq(2)

      # First abstract method
      method1 = arena[class_body[0]]
      Adamas::Compiler::Frontend.node_def_is_abstract(method1).should be_truthy
      String.new(Adamas::Compiler::Frontend.node_def_name(method1).not_nil!).should eq("area")

      # Second abstract method
      method2 = arena[class_body[1]]
      Adamas::Compiler::Frontend.node_def_is_abstract(method2).should be_truthy
      String.new(Adamas::Compiler::Frontend.node_def_name(method2).not_nil!).should eq("perimeter")
    end

    it "parses abstract class with concrete methods" do
      source = <<-CRYSTAL
      abstract class Shape
        abstract def area : Float64

        def describe
          puts "I am a shape"
        end
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena
      class_node = arena[program.roots.first]

      class_body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
      class_body.size.should eq(2)

      # Abstract method
      abstract_method = arena[class_body[0]]
      Adamas::Compiler::Frontend.node_def_is_abstract(abstract_method).should be_truthy
      Adamas::Compiler::Frontend.node_def_body(abstract_method).should be_nil

      # Concrete method
      concrete_method = arena[class_body[1]]
      Adamas::Compiler::Frontend.node_def_is_abstract(concrete_method).should be_falsey
      Adamas::Compiler::Frontend.node_def_body(concrete_method).should_not be_nil
    end

    it "distinguishes abstract from non-abstract class" do
      source = <<-CRYSTAL
      abstract class AbstractShape
      end

      class ConcreteShape
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(2)
      arena = program.arena

      # Abstract class
      abstract_class = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_class_is_abstract(abstract_class).should be_truthy

      # Concrete class
      concrete_class = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_class_is_abstract(concrete_class).should be_falsey
    end

    it "parses abstract class with inheritance" do
      source = <<-CRYSTAL
      abstract class Animal < LivingThing
        abstract def speak : String
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena
      class_node = arena[program.roots.first]

      Adamas::Compiler::Frontend.node_class_is_abstract(class_node).should be_truthy
      String.new(Adamas::Compiler::Frontend.node_class_super_name(class_node).not_nil!).should eq("LivingThing")
    end

    it "parses nested abstract classes" do
      source = <<-CRYSTAL
      class Outer
        abstract class Inner
          abstract def process
        end
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena
      outer_class = arena[program.roots.first]

      outer_body = Adamas::Compiler::Frontend.node_class_body(outer_class).not_nil!
      outer_body.size.should eq(1)

      inner_class = arena[outer_body[0]]
      Adamas::Compiler::Frontend.node_class_is_abstract(inner_class).should be_truthy
    end

    it "parses abstract method with parameters" do
      source = <<-CRYSTAL
      abstract class Calculator
        abstract def compute(x : Int32, y : Int32) : Int32
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena
      class_node = arena[program.roots.first]

      class_body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
      method_node = arena[class_body[0]]

      Adamas::Compiler::Frontend.node_def_is_abstract(method_node).should be_truthy
      params = Adamas::Compiler::Frontend.node_def_params(method_node).not_nil!
      params.size.should eq(2)
      params[0].name.should eq("x".to_slice)
      params[1].name.should eq("y".to_slice)
    end
  end
end
