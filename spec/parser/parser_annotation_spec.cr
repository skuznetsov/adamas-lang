require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 92: annotation keyword (user-defined annotation declarations)" do
    it "parses annotation arguments containing macro expressions" do
      source = <<-CRYSTAL
      @[Link({{ flag?(:static) ? "libucrt" : "ucrt" }})]
      lib ProbeLib
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      parser.diagnostics.should be_empty
      program.roots.size.should eq(2)

      arena = program.arena
      annotation_node = arena[program.roots[0]].as(Adamas::Compiler::Frontend::AnnotationNode)
      annotation_node.args.size.should eq(1)

      macro_expr = arena[annotation_node.args[0]].as(Adamas::Compiler::Frontend::MacroExpressionNode)
      Adamas::Compiler::Frontend.node_macro_expr(macro_expr).should_not be_nil
    end

    it "parses simple annotation definition" do
      source = <<-CRYSTAL
      annotation MyAnnotation
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      annotation_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(annotation_node).should eq(Adamas::Compiler::Frontend::NodeKind::AnnotationDef)

      # Check name
      name = Adamas::Compiler::Frontend.node_annotation_name(annotation_node)
      name.should_not be_nil
      name.not_nil!.should eq("MyAnnotation".to_slice)
    end

    it "parses annotation inside class" do
      source = <<-CRYSTAL
      class Foo
        annotation Internal
        end
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      class_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(class_node).should eq(Adamas::Compiler::Frontend::NodeKind::Class)

      class_body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
      class_body.size.should eq(1)

      annotation_node = arena[class_body[0]]
      Adamas::Compiler::Frontend.node_kind(annotation_node).should eq(Adamas::Compiler::Frontend::NodeKind::AnnotationDef)
      Adamas::Compiler::Frontend.node_annotation_name(annotation_node).not_nil!.should eq("Internal".to_slice)
    end

    it "parses annotation inside module" do
      source = <<-CRYSTAL
      module MyModule
        annotation Helper
        end
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      module_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(module_node).should eq(Adamas::Compiler::Frontend::NodeKind::Module)

      module_body = Adamas::Compiler::Frontend.node_module_body(module_node).not_nil!
      module_body.size.should eq(1)

      annotation_node = arena[module_body[0]]
      Adamas::Compiler::Frontend.node_kind(annotation_node).should eq(Adamas::Compiler::Frontend::NodeKind::AnnotationDef)
      Adamas::Compiler::Frontend.node_annotation_name(annotation_node).not_nil!.should eq("Helper".to_slice)
    end

    it "parses multiple annotations" do
      source = <<-CRYSTAL
      annotation First
      end

      annotation Second
      end

      annotation Third
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(3)
      arena = program.arena

      # First annotation
      ann1 = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(ann1).should eq(Adamas::Compiler::Frontend::NodeKind::AnnotationDef)
      Adamas::Compiler::Frontend.node_annotation_name(ann1).not_nil!.should eq("First".to_slice)

      # Second annotation
      ann2 = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_kind(ann2).should eq(Adamas::Compiler::Frontend::NodeKind::AnnotationDef)
      Adamas::Compiler::Frontend.node_annotation_name(ann2).not_nil!.should eq("Second".to_slice)

      # Third annotation
      ann3 = arena[program.roots[2]]
      Adamas::Compiler::Frontend.node_kind(ann3).should eq(Adamas::Compiler::Frontend::NodeKind::AnnotationDef)
      Adamas::Compiler::Frontend.node_annotation_name(ann3).not_nil!.should eq("Third".to_slice)
    end

    it "parses annotation with body (Phase 92A: body skipped)" do
      source = <<-CRYSTAL
      annotation MyAnnotation
        getter value : String
        getter count : Int32
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      annotation_node = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(annotation_node).should eq(Adamas::Compiler::Frontend::NodeKind::AnnotationDef)
      Adamas::Compiler::Frontend.node_annotation_name(annotation_node).not_nil!.should eq("MyAnnotation".to_slice)

      # Phase 92A: Body is skipped/ignored for now
      # Body parsing will be Phase 92B if needed
    end

    it "parses annotation before class definition" do
      source = <<-CRYSTAL
      annotation Deprecated
      end

      class Foo
      end
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(2)
      arena = program.arena

      # First root is annotation
      ann = arena[program.roots[0]]
      Adamas::Compiler::Frontend.node_kind(ann).should eq(Adamas::Compiler::Frontend::NodeKind::AnnotationDef)

      # Second root is class
      cls = arena[program.roots[1]]
      Adamas::Compiler::Frontend.node_kind(cls).should eq(Adamas::Compiler::Frontend::NodeKind::Class)
    end
  end
end
