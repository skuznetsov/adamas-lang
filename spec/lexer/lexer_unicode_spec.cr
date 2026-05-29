require "spec"

require "../../src/compiler/frontend/parser"

describe "Adamas::Compiler::Frontend::Parser" do
  describe "Phase 58: Unicode escapes (PRODUCTION-READY)" do
    # String literal tests

    it "parses \\uXXXX ASCII in string" do
      source = "s = \"\\u0041\""  # 'A'

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(string_node).should eq(Adamas::Compiler::Frontend::NodeKind::String)
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("A")
    end

    it "parses \\uXXXX BMP character in string" do
      source = "s = \"\\u4E00\""  # Chinese character '一'

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("一")
    end

    it "parses \\u{X} variable length in string" do
      source = "s = \"\\u{41}\""  # 'A' with variable length

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("A")
    end

    it "parses \\u{XXXX} emoji in string" do
      source = "s = \"\\u{1F600}\""  # Grinning face emoji 😀

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("😀")
    end

    it "parses multiple Unicode escapes in string" do
      source = "s = \"\\u0041\\u0042\\u0043\""  # "ABC"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("ABC")
    end

    it "parses mixed Unicode and regular text in string" do
      source = "s = \"Hello \\u{1F44B} World\""  # "Hello 👋 World"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("Hello 👋 World")
    end

    it "parses mixed Unicode and escape sequences in string" do
      source = "s = \"\\u0041\\nB\""  # "A\nB"

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("A\nB")
    end

    # Character literal tests

    it "parses \\uXXXX ASCII in character" do
      source = "c = '\\u0041'"  # 'A'

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      char_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      Adamas::Compiler::Frontend.node_kind(char_node).should eq(Adamas::Compiler::Frontend::NodeKind::Char)
      String.new(Adamas::Compiler::Frontend.node_literal(char_node).not_nil!).should eq("A")
    end

    it "parses \\uXXXX BMP character in character literal" do
      source = "c = '\\u4E00'"  # Chinese character '一'

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      char_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(char_node).not_nil!).should eq("一")
    end

    it "parses \\u{X} variable length in character" do
      source = "c = '\\u{42}'"  # 'B' with variable length

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      char_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(char_node).not_nil!).should eq("B")
    end

    it "parses \\u{XXXX} emoji in character" do
      source = "c = '\\u{1F602}'"  # Face with tears of joy emoji 😂

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      char_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(char_node).not_nil!).should eq("😂")
    end

    # UTF-8 encoding tests

    it "parses 2-byte UTF-8 sequence" do
      source = "s = \"\\u00A9\""  # Copyright symbol ©

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("©")
    end

    it "parses 3-byte UTF-8 sequence" do
      source = "s = \"\\u2603\""  # Snowman ☃

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("☃")
    end

    it "parses 4-byte UTF-8 sequence" do
      source = "s = \"\\u{1F44D}\""  # Thumbs up 👍

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      assign = arena[program.roots[0]]
      string_node = arena[Adamas::Compiler::Frontend.node_assign_value(assign).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("👍")
    end

    # Integration tests

    it "parses Unicode in array" do
      source = "[\"\\u0041\", \"\\u{1F600}\"]"  # ["A", "😀"]

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
      String.new(Adamas::Compiler::Frontend.node_literal(str2).not_nil!).should eq("😀")
    end

    it "parses Unicode in method call" do
      source = "puts(\"\\u{1F389}\")"  # puts("🎉")

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(1)
      arena = program.arena

      call = arena[program.roots[0]]
      args = Adamas::Compiler::Frontend.node_args(call).not_nil!
      args.size.should eq(1)

      string_node = arena[args[0]]
      String.new(Adamas::Compiler::Frontend.node_literal(string_node).not_nil!).should eq("🎉")
    end

    it "parses multiple statements with Unicode" do
      source = <<-CRYSTAL
      a = "\\u0048ello"
      b = '\\u{1F44B}'
      c = "\\u4E00\\u4E8C\\u4E09"
      CRYSTAL

      parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
      program = parser.parse_program

      program.roots.size.should eq(3)
      arena = program.arena

      # First: "Hello"
      assign1 = arena[program.roots[0]]
      str1 = arena[Adamas::Compiler::Frontend.node_assign_value(assign1).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(str1).not_nil!).should eq("Hello")

      # Second: '👋'
      assign2 = arena[program.roots[1]]
      char2 = arena[Adamas::Compiler::Frontend.node_assign_value(assign2).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(char2).not_nil!).should eq("👋")

      # Third: "一二三"
      assign3 = arena[program.roots[2]]
      str3 = arena[Adamas::Compiler::Frontend.node_assign_value(assign3).not_nil!]
      String.new(Adamas::Compiler::Frontend.node_literal(str3).not_nil!).should eq("一二三")
    end
  end
end
