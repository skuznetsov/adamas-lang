require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 34: Alias definition (PRODUCTION-READY)" do
  it "parses simple type alias" do
    source = "alias MyInt = Int32"
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    program.roots.size.should eq(1)
    arena = program.arena
    alias_node = arena[program.roots.first]

    Adamas::Compiler::Frontend.node_kind(alias_node).should eq(Adamas::Compiler::Frontend::NodeKind::Alias)
    Adamas::Compiler::Frontend.node_alias_name(alias_node).should_not be_nil
    String.new(Adamas::Compiler::Frontend.node_alias_name(alias_node).not_nil!).should eq("MyInt")
    Adamas::Compiler::Frontend.node_alias_value(alias_node).should_not be_nil
    String.new(Adamas::Compiler::Frontend.node_alias_value(alias_node).not_nil!).should eq("Int32")
  end

  it "parses multiple aliases" do
    source = <<-CRYSTAL
    alias MyInt = Int32
    alias MyString = String
    alias MyFloat = Float64
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    program.roots.size.should eq(3)
    arena = program.arena

    # First alias
    alias1 = arena[program.roots[0]]
    Adamas::Compiler::Frontend.node_kind(alias1).should eq(Adamas::Compiler::Frontend::NodeKind::Alias)
    String.new(Adamas::Compiler::Frontend.node_alias_name(alias1).not_nil!).should eq("MyInt")
    String.new(Adamas::Compiler::Frontend.node_alias_value(alias1).not_nil!).should eq("Int32")

    # Second alias
    alias2 = arena[program.roots[1]]
    String.new(Adamas::Compiler::Frontend.node_alias_name(alias2).not_nil!).should eq("MyString")
    String.new(Adamas::Compiler::Frontend.node_alias_value(alias2).not_nil!).should eq("String")

    # Third alias
    alias3 = arena[program.roots[2]]
    String.new(Adamas::Compiler::Frontend.node_alias_name(alias3).not_nil!).should eq("MyFloat")
    String.new(Adamas::Compiler::Frontend.node_alias_value(alias3).not_nil!).should eq("Float64")
  end

  it "parses alias in class" do
    source = <<-CRYSTAL
    class MyClass
      alias MyType = String
    end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    program.roots.size.should eq(1)
    arena = program.arena
    class_node = arena[program.roots.first]
    Adamas::Compiler::Frontend.node_kind(class_node).should eq(Adamas::Compiler::Frontend::NodeKind::Class)

    class_body = Adamas::Compiler::Frontend.node_class_body(class_node).not_nil!
    class_body.size.should eq(1)

    alias_node = arena[class_body[0]]
    Adamas::Compiler::Frontend.node_kind(alias_node).should eq(Adamas::Compiler::Frontend::NodeKind::Alias)
    String.new(Adamas::Compiler::Frontend.node_alias_name(alias_node).not_nil!).should eq("MyType")
    String.new(Adamas::Compiler::Frontend.node_alias_value(alias_node).not_nil!).should eq("String")
  end

  it "parses alias in module" do
    source = <<-CRYSTAL
    module MyModule
      alias MyType = Int32
    end
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    program.roots.size.should eq(1)
    arena = program.arena
    module_node = arena[program.roots.first]
    Adamas::Compiler::Frontend.node_kind(module_node).should eq(Adamas::Compiler::Frontend::NodeKind::Module)

    module_body = Adamas::Compiler::Frontend.node_module_body(module_node).not_nil!
    module_body.size.should eq(1)

    alias_node = arena[module_body[0]]
    Adamas::Compiler::Frontend.node_kind(alias_node).should eq(Adamas::Compiler::Frontend::NodeKind::Alias)
    String.new(Adamas::Compiler::Frontend.node_alias_name(alias_node).not_nil!).should eq("MyType")
    String.new(Adamas::Compiler::Frontend.node_alias_value(alias_node).not_nil!).should eq("Int32")
  end

  it "parses complex type aliases" do
    source = <<-CRYSTAL
    alias IntArray = Array
    alias StringHash = Hash
    alias MyCallback = Proc
    CRYSTAL

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    program.roots.size.should eq(3)
    arena = program.arena

    # First alias
    alias1 = arena[program.roots[0]]
    String.new(Adamas::Compiler::Frontend.node_alias_name(alias1).not_nil!).should eq("IntArray")
    String.new(Adamas::Compiler::Frontend.node_alias_value(alias1).not_nil!).should eq("Array")

    # Second alias
    alias2 = arena[program.roots[1]]
    String.new(Adamas::Compiler::Frontend.node_alias_name(alias2).not_nil!).should eq("StringHash")
    String.new(Adamas::Compiler::Frontend.node_alias_value(alias2).not_nil!).should eq("Hash")

    # Third alias
    alias3 = arena[program.roots[2]]
    String.new(Adamas::Compiler::Frontend.node_alias_name(alias3).not_nil!).should eq("MyCallback")
    String.new(Adamas::Compiler::Frontend.node_alias_value(alias3).not_nil!).should eq("Proc")
  end

  it "parses alias with qualified type name" do
    source = "alias MyType = HTTP"

    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program

    program.roots.size.should eq(1)
    arena = program.arena
    alias_node = arena[program.roots.first]

    Adamas::Compiler::Frontend.node_kind(alias_node).should eq(Adamas::Compiler::Frontend::NodeKind::Alias)
    String.new(Adamas::Compiler::Frontend.node_alias_name(alias_node).not_nil!).should eq("MyType")
    String.new(Adamas::Compiler::Frontend.node_alias_value(alias_node).not_nil!).should eq("HTTP")
  end
  end
end
