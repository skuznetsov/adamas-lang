require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 32: Struct definition (PRODUCTION-READY)" do
    it "parses empty struct" do
      source = <<-CRYSTAL
        struct Point
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      struct_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(struct_node).should eq(Adamas::Compiler::Frontend::NodeKind::Struct)

      struct_name = String.new(Adamas::Compiler::Frontend.node_class_name(struct_node).not_nil!)
      struct_name.should eq("Point")

      struct_node.as(Adamas::Compiler::Frontend::ClassNode).is_struct.should eq(true)

      struct_body = Adamas::Compiler::Frontend.node_class_body(struct_node).not_nil!
      struct_body.size.should eq(0)
    end

    it "parses struct with instance variables" do
      source = <<-CRYSTAL
        struct Point
          @x : Int32
          @y : Int32
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      arena = program.arena
      struct_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(struct_node).should eq(Adamas::Compiler::Frontend::NodeKind::Struct)

      struct_body = Adamas::Compiler::Frontend.node_class_body(struct_node).not_nil!
      struct_body.size.should eq(2)

      # First instance variable
      ivar1 = arena[struct_body[0]]
      Adamas::Compiler::Frontend.node_kind(ivar1).should eq(Adamas::Compiler::Frontend::NodeKind::InstanceVarDecl)

      # Second instance variable
      ivar2 = arena[struct_body[1]]
      Adamas::Compiler::Frontend.node_kind(ivar2).should eq(Adamas::Compiler::Frontend::NodeKind::InstanceVarDecl)
    end

    it "parses struct with methods" do
      source = <<-CRYSTAL
        struct Point
          def initialize(@x, @y)
          end

          def distance
            Math.sqrt(@x * @x + @y * @y)
          end
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      arena = program.arena
      struct_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(struct_node).should eq(Adamas::Compiler::Frontend::NodeKind::Struct)
      struct_node.as(Adamas::Compiler::Frontend::ClassNode).is_struct.should eq(true)

      struct_body = Adamas::Compiler::Frontend.node_class_body(struct_node).not_nil!
      struct_body.size.should eq(2)

      # initialize method
      init_method = arena[struct_body[0]]
      Adamas::Compiler::Frontend.node_kind(init_method).should eq(Adamas::Compiler::Frontend::NodeKind::Def)

      # distance method
      distance_method = arena[struct_body[1]]
      Adamas::Compiler::Frontend.node_kind(distance_method).should eq(Adamas::Compiler::Frontend::NodeKind::Def)
    end

    it "parses struct with getter/setter" do
      source = <<-CRYSTAL
        struct Person
          getter name : String
          setter age : Int32
          property email : String
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      arena = program.arena
      struct_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(struct_node).should eq(Adamas::Compiler::Frontend::NodeKind::Struct)

      struct_body = Adamas::Compiler::Frontend.node_class_body(struct_node).not_nil!
      struct_body.size.should eq(3)

      # Getter
      getter_node = arena[struct_body[0]]
      Adamas::Compiler::Frontend.node_kind(getter_node).should eq(Adamas::Compiler::Frontend::NodeKind::Getter)

      # Setter
      setter_node = arena[struct_body[1]]
      Adamas::Compiler::Frontend.node_kind(setter_node).should eq(Adamas::Compiler::Frontend::NodeKind::Setter)

      # Property
      property_node = arena[struct_body[2]]
      Adamas::Compiler::Frontend.node_kind(property_node).should eq(Adamas::Compiler::Frontend::NodeKind::Property)
    end

    it "parses struct with superclass" do
      source = <<-CRYSTAL
        struct Rectangle < Shape
          def area
            width * height
          end
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      arena = program.arena
      struct_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(struct_node).should eq(Adamas::Compiler::Frontend::NodeKind::Struct)
      struct_node.as(Adamas::Compiler::Frontend::ClassNode).is_struct.should eq(true)

      struct_name = String.new(Adamas::Compiler::Frontend.node_class_name(struct_node).not_nil!)
      struct_name.should eq("Rectangle")

      super_name = String.new(Adamas::Compiler::Frontend.node_class_super_name(struct_node).not_nil!)
      super_name.should eq("Shape")
    end

    it "parses nested struct in class" do
      source = <<-CRYSTAL
        class Container
          struct InnerStruct
            getter value : Int32
          end
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      arena = program.arena
      class_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(class_node).should eq(Adamas::Compiler::Frontend::NodeKind::Class)

      class_body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
      class_body.size.should eq(1)

      # Nested struct
      struct_node = arena[class_body[0]]
      Adamas::Compiler::Frontend.node_kind(struct_node).should eq(Adamas::Compiler::Frontend::NodeKind::Struct)
      struct_node.as(Adamas::Compiler::Frontend::ClassNode).is_struct.should eq(true)
    end

    it "parses struct with include and extend" do
      source = <<-CRYSTAL
        struct Advanced
          include Comparable
          extend ClassMethods

          getter value : Int32
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      arena = program.arena
      struct_node = arena[program.roots.first]
      Adamas::Compiler::Frontend.node_kind(struct_node).should eq(Adamas::Compiler::Frontend::NodeKind::Struct)

      struct_body = Adamas::Compiler::Frontend.node_class_body(struct_node).not_nil!
      struct_body.size.should eq(3)

      # Include
      include_node = arena[struct_body[0]]
      Adamas::Compiler::Frontend.node_kind(include_node).should eq(Adamas::Compiler::Frontend::NodeKind::Include)

      # Extend
      extend_node = arena[struct_body[1]]
      Adamas::Compiler::Frontend.node_kind(extend_node).should eq(Adamas::Compiler::Frontend::NodeKind::Extend)

      # Getter
      getter_node = arena[struct_body[2]]
      Adamas::Compiler::Frontend.node_kind(getter_node).should eq(Adamas::Compiler::Frontend::NodeKind::Getter)
    end

    it "distinguishes between class and struct" do
      source = <<-CRYSTAL
        class MyClass
        end

        struct MyStruct
        end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(2)
      arena = program.arena

      # First is class
      class_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(class_node).should eq(Adamas::Compiler::Frontend::NodeKind::Class)
      class_node.as(Adamas::Compiler::Frontend::ClassNode).is_struct.should be_falsey  # nil or false

      # Second is struct
      struct_node = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_kind(struct_node).should eq(Adamas::Compiler::Frontend::NodeKind::Struct)
      struct_node.as(Adamas::Compiler::Frontend::ClassNode).is_struct.should eq(true)
    end
  end
end
