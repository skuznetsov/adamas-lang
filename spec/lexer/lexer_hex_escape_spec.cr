require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 59: Hex escape sequences (PRODUCTION-READY)" do
    # String literal tests

    it "parses \\xXX ASCII in string" do
      source = "s = \"\\x41\""  # 'A'

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(string_node).should eq(Adamas::Compiler::Frontend::NodeKind::String)
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("A")
    end

    it "parses \\xXX control character in string" do
      source = "s = \"\\x0A\""  # newline

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("\n")
    end

    it "parses \\xXX null byte in string" do
      source = "s = \"\\x00\""  # null

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("\0")
    end

    it "parses \\xXX high byte in string" do
      source = "s = \"\\xFF\""  # 255

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      bytes = Adamas::Compiler::Frontend.node_literal(string_node).not_nil!
      bytes.size.should eq(1)
      bytes[0].should eq(0xFF_u8)
    end

    it "parses multiple \\xXX in string" do
      source = "s = \"\\x41\\x42\\x43\""  # "ABC"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("ABC")
    end

    it "parses mixed hex and regular text in string" do
      source = "s = \"Hello\\x20World\""  # "Hello World"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("Hello World")
    end

    it "parses mixed hex and other escapes in string" do
      source = "s = \"\\x41\\nB\""  # "A\nB"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("A\nB")
    end

    it "parses lowercase hex digits in string" do
      source = "s = \"\\x61\""  # 'a'

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("a")
    end

    # Character literal tests

    it "parses \\xXX ASCII in character" do
      source = "c = '\\x41'"  # 'A'

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      char_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(char_node).should eq(Adamas::Compiler::Frontend::NodeKind::Char)
      String.new(Adamas::Compiler::Frontend.node_literal(char_node).not_nil!).should eq("A")
    end

    it "parses \\xXX control character in character literal" do
      source = "c = '\\x09'"  # tab

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      char_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(char_node).not_nil!).should eq("\t")
    end

    it "parses \\xXX null byte in character" do
      source = "c = '\\x00'"  # null

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      char_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(char_node).not_nil!).should eq("\0")
    end

    it "parses \\xXX high byte in character" do
      source = "c = '\\xFF'"  # 255

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      char_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      bytes = Adamas::Compiler::Frontend.node_literal(char_node).not_nil!
      bytes.size.should eq(1)
      bytes[0].should eq(0xFF_u8)
    end

    # Integration tests

    it "parses hex escapes in array" do
      source = "[\"\\x41\", \"\\x42\"]"  # ["A", "B"]

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      array = arena[program.roots[0]]
      elements = Adamas::Compiler::Frontend.node_array_elements(array).not_nil!
      elements.size.should eq(2)

      str1 = arena[elements[0]]
      String.new(Adamas::Compiler::Frontend.node_literal(str1).not_nil!).should eq("A")

      str2 = arena[elements[1]]
      String.new(Adamas::Compiler::Frontend.node_literal(str2).not_nil!).should eq("B")
    end

    it "parses hex escapes in method call" do
      source = "puts(\"\\x48ello\")"  # puts("Hello")

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call = arena[program.roots[0]]
      args = Adamas::Compiler::Frontend.node_args(call).not_nil!
      args.size.should eq(1)

      string_node = arena[args[0]]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("Hello")
    end

    it "parses multiple statements with hex escapes" do
      source = <<-CRYSTAL
      a = "\\x48ello"
      b = '\\x41'
      c = "\\x31\\x32\\x33"
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(3)
      arena = program.arena

      # First: "Hello"
      assign1 = arena[program.roots[0]]
      str1 = arena[Adamas::Compiler::Frontend.node_assign_value(assign1).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(str1).not_nil!).should eq("Hello")

      # Second: 'A'
      assign2 = arena[program.roots[1]]
      char2 = arena[Adamas::Compiler::Frontend.node_assign_value(assign2).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(char2).not_nil!).should eq("A")

      # Third: "123"
      assign3 = arena[program.roots[2]]
      str3 = arena[Adamas::Compiler::Frontend.node_assign_value(assign3).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(str3).not_nil!).should eq("123")
    end
  end
end
