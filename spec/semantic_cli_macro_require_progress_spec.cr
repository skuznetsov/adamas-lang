require "./semantic_cli_helpers"

include SemanticCliSpecHelpers

module Adamas::Compiler
  class CLI
    def macro_require_piece_texts_for_spec(
      pieces : Array(Frontend::MacroPiece),
      arena : Frontend::AstArena = Frontend::AstArena.new,
    ) : Array(String)
      node = Frontend::MacroLiteralNode.new(Frontend::Span.zero, pieces, false, false)
      macro_literal_require_texts(arena, node, Set(String).new)
    end

    def macro_require_raw_texts_for_spec(source : String) : Array(String)
      macro_literal_texts_from_raw(source, Set(String).new)
    end
  end
end

alias RequireProgressFrontend = Adamas::Compiler::Frontend

describe "CLI macro require scanner progress" do
  it "advances past a fragment's unmatched else and elsif pieces" do
    cli = Adamas::Compiler::CLI.new([] of String)
    [
      {RequireProgressFrontend::MacroPiece::Kind::ControlElse, "else"},
      {RequireProgressFrontend::MacroPiece::Kind::ControlElseIf, "elsif"},
    ].each do |kind, keyword|
      pieces = [
        RequireProgressFrontend::MacroPiece.text("before\n"),
        RequireProgressFrontend::MacroPiece.control(kind, keyword),
        RequireProgressFrontend::MacroPiece.text("require \"./after\"\n"),
      ]
      cli.macro_require_piece_texts_for_spec(pieces).should eq([
        "before\n", "require \"./after\"\n",
      ])
    end
  end

  it "consumes unmatched raw control tags without emitting them as require text" do
    cli = Adamas::Compiler::CLI.new([] of String)
    ["else", "elsif true"].each do |tag|
      source = "before\n{% #{tag} %}require \"./after\"\n"
      cli.macro_require_raw_texts_for_spec(source).should eq([
        "before\n", "require \"./after\"\n",
      ])
    end
  end

  it "preserves known branch selection in piece scanning" do
    arena = RequireProgressFrontend::AstArena.new
    parsed = RequireProgressFrontend::Parser.new(
      RequireProgressFrontend::Lexer.new("false\ntrue\n"), arena
    ).parse_program
    pieces = [
      RequireProgressFrontend::MacroPiece.control(
        RequireProgressFrontend::MacroPiece::Kind::ControlStart, "if", parsed.roots[0]
      ),
      RequireProgressFrontend::MacroPiece.text("require \"./inactive\"\n"),
      RequireProgressFrontend::MacroPiece.control(
        RequireProgressFrontend::MacroPiece::Kind::ControlElseIf, "elsif", parsed.roots[1]
      ),
      RequireProgressFrontend::MacroPiece.text("require \"./active\"\n"),
      RequireProgressFrontend::MacroPiece.control(
        RequireProgressFrontend::MacroPiece::Kind::ControlElse, "else"
      ),
      RequireProgressFrontend::MacroPiece.text("require \"./inactive_else\"\n"),
      RequireProgressFrontend::MacroPiece.control(
        RequireProgressFrontend::MacroPiece::Kind::ControlEnd, "end"
      ),
      RequireProgressFrontend::MacroPiece.text("require \"./after\"\n"),
    ]
    cli = Adamas::Compiler::CLI.new([] of String)
    cli.macro_require_piece_texts_for_spec(pieces, arena).should eq([
      "require \"./active\"\n", "require \"./after\"\n",
    ])
  end

  it "ignores control-looking tags inside strings and comments" do
    cli = Adamas::Compiler::CLI.new([] of String)
    source = "value = \"{% else %}\"\n# {% elsif false %}\nrequire \"./after\"\n"
    cli.macro_require_raw_texts_for_spec(source).should eq([source])
  end

  it "restores the parent branch after nested raw conditionals" do
    cli = Adamas::Compiler::CLI.new([] of String)
    source = <<-CRYSTAL
      {% if true %}require "./outer"
      {% if false %}require "./inactive"
      {% else %}require "./nested"
      {% end %}require "./after_nested"
      {% else %}require "./inactive_outer"
      {% end %}require "./after"
      CRYSTAL
    cli.macro_require_raw_texts_for_spec(source).should eq([
      "require \"./outer\"\n", "require \"./nested\"\n",
      "require \"./after_nested\"\n", "require \"./after\"",
    ])
  end

  it "does not scan an unterminated raw control tag as require text" do
    cli = Adamas::Compiler::CLI.new([] of String)
    cli.macro_require_raw_texts_for_spec("before\n{% elsif require \"./partial\"").should eq(["before\n"])
  end

  it "loads a required file from a valid conditional macro" do
    with_temp_shadow_project({
      "main.cr" => <<-CRYSTAL,
        {% if false %}
          require "./inactive"
        {% elsif true %}
          require "./active"
        {% else %}
          require "./inactive_else"
        {% end %}
        puts MacroRequireProgress::VALUE
        CRYSTAL
      "active.cr" => "module MacroRequireProgress; VALUE = 73; end\n",
    }) do |dir|
      output = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = Adamas::Compiler::CLI.new([
        File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir", "--no-link", "--verbose",
        "-o", output,
      ]).run(out_io: out_io, err_io: err_io)
      status.should eq(0), err_io.to_s
      out_io.to_s.should contain("Loading: #{File.join(dir, "active.cr")}")
      out_io.to_s.should_not contain("Loading: #{File.join(dir, "inactive.cr")}")
      File.read("#{output}.hir").should contain("classvar_get MacroRequireProgress.@@VALUE")
    end
  end
end
