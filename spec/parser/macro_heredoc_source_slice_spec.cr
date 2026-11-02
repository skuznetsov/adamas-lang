require "spec"

require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"

alias MacroHeredocSourceSliceFrontend = Adamas::Compiler::Frontend

private def macro_heredoc_source_slice_parse(source : String) : {MacroHeredocSourceSliceFrontend::Program, String}
  parser = MacroHeredocSourceSliceFrontend::Parser.new(
    MacroHeredocSourceSliceFrontend::Lexer.new(source)
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.ast_arena
  definition_id = program.roots.find do |root|
    arena[root].is_a?(MacroHeredocSourceSliceFrontend::MacroDefNode)
  end.not_nil!
  definition = arena[definition_id].as(MacroHeredocSourceSliceFrontend::MacroDefNode)
  body = arena[definition.body].as(MacroHeredocSourceSliceFrontend::MacroLiteralNode)
  text = body.pieces.compact_map(&.text).join

  {program, text}
end

private def macro_heredoc_span_source(source : String, span : MacroHeredocSourceSliceFrontend::Span) : String
  String.new(source.to_slice[span.start_offset, span.end_offset - span.start_offset])
end

private def macro_heredoc_fixture_parse(name : String)
  source = File.read(File.join(__DIR__, "../fixtures/macro_heredoc_source_slice", name))
  macro_heredoc_source_slice_parse(source)
end

private def macro_heredoc_literal(program : MacroHeredocSourceSliceFrontend::Program) : MacroHeredocSourceSliceFrontend::MacroLiteralNode
  arena = program.ast_arena
  definition_id = program.roots.find do |root|
    arena[root].is_a?(MacroHeredocSourceSliceFrontend::MacroDefNode)
  end.not_nil!
  definition = arena[definition_id].as(MacroHeredocSourceSliceFrontend::MacroDefNode)
  arena[definition.body].as(MacroHeredocSourceSliceFrontend::MacroLiteralNode)
end

describe "Macro heredoc source slices" do
  it "keeps the semantic span while exposing disjoint opener and body source spans" do
    source = "sink(<<-BODY, 7)\nfirst payload\nBODY\n"
    tokens = [] of MacroHeredocSourceSliceFrontend::Token
    MacroHeredocSourceSliceFrontend::Lexer.new(source).each_token { |token| tokens << token }
    token = tokens.find { |candidate| candidate.kind == MacroHeredocSourceSliceFrontend::Token::Kind::String }.not_nil!
    heredoc = token.heredoc_source.not_nil!

    macro_heredoc_span_source(source, heredoc.opener_span).should eq("<<-BODY")
    macro_heredoc_span_source(source, heredoc.body_span).should eq("first payload\nBODY\n")
    token.span.start_offset.should eq(heredoc.opener_span.start_offset)
    token.span.end_offset.should eq(heredoc.body_span.end_offset)
  end

  it "reconstructs a heredoc with sibling arguments exactly once and resumes after the macro" do
    source = "macro emit\nsink(<<-BODY, 7)\nfirst payload\nBODY\nend\nafter_macro = 1\n"
    program, body_text = macro_heredoc_source_slice_parse(source)

    body_text.should eq("sink(<<-BODY, 7)\nfirst payload\nBODY\n")
    program.roots.size.should eq(2)
    program.ast_arena[program.roots[1]].should be_a(MacroHeredocSourceSliceFrontend::AssignNode)
  end

  it "reconstructs multiple heredocs in physical source order exactly once" do
    source = "macro emit_pair\nsink(<<-FIRST, <<-SECOND)\nfirst payload\nFIRST\nsecond payload\nSECOND\nend\nafter_macro = 1\n"
    program, body_text = macro_heredoc_source_slice_parse(source)

    body_text.should eq("sink(<<-FIRST, <<-SECOND)\nfirst payload\nFIRST\nsecond payload\nSECOND\n")
    program.roots.size.should eq(2)
    program.ast_arena[program.roots[1]].should be_a(MacroHeredocSourceSliceFrontend::AssignNode)
  end

  it "retains a block opener after a heredoc argument without swallowing the next root" do
    source = "macro emit\neach_code(<<-BODY) do |code|\npayload\nBODY\ncode\nend\nend\nafter_macro = 1\n"
    program, body_text = macro_heredoc_source_slice_parse(source)

    body_text.should eq("each_code(<<-BODY) do |code|\npayload\nBODY\ncode\nend\n")
    program.roots.size.should eq(2)
    program.ast_arena[program.roots[1]].should be_a(MacroHeredocSourceSliceFrontend::AssignNode)
  end

  it "keeps CRLF bytes in macro heredoc source" do
    source = "macro emit\nsink(<<-BODY)\r\nfirst payload\r\nBODY\r\nend\r\n"
    _, body_text = macro_heredoc_source_slice_parse(source)

    body_text.should eq("sink(<<-BODY)\r\nfirst payload\r\nBODY\r\n")
  end

  it "treats CRLF as one newline token" do
    diagnostics = [] of MacroHeredocSourceSliceFrontend::Diagnostic
    tokens = [] of MacroHeredocSourceSliceFrontend::Token
    lexer = MacroHeredocSourceSliceFrontend::Lexer.new("left\r\nright", diagnostics: diagnostics)
    lexer.each_token { |token| tokens << token }

    diagnostics.should be_empty
    tokens.count { |token| token.kind == MacroHeredocSourceSliceFrontend::Token::Kind::Newline }.should eq(1)
  end

  it "keeps embedded directives in heredoc bodies and opener tails as macro pieces" do
    source = "macro emit\nsink(<<-BODY, {{ \"tail\".id }})\n{{ \"payload\".id }}\nBODY\nend\n"
    program, body_text = macro_heredoc_source_slice_parse(source)
    definition = program.ast_arena[program.roots.first].as(MacroHeredocSourceSliceFrontend::MacroDefNode)
    body = program.ast_arena[definition.body].as(MacroHeredocSourceSliceFrontend::MacroLiteralNode)

    body_text.should eq("sink(<<-BODY, )\n\nBODY\n")
    body.pieces.count { |piece| piece.kind == MacroHeredocSourceSliceFrontend::MacroPiece::Kind::Expression }.should eq(2)
  end

  it "does not publish a heredoc body consumed by a macro control expression" do
    source = "macro emit\nsink(<<-RAW)\nraw payload\nRAW\n{% text = <<-CONTROL\ncontrol payload\nCONTROL\n%}\nend\n"
    _, body_text = macro_heredoc_source_slice_parse(source)

    body_text.should contain("raw payload")
    body_text.should_not contain("control payload")
  end

  it "preserves the stock sibling-argument heredoc source" do
    _, body_text = macro_heredoc_fixture_parse("macro_sibling.cr")

    body_text.should contain("select_number(<<-BODY, 65)")
    body_text.split("payload").size.should eq(2)
  end

  it "preserves multiple stock heredoc bodies in physical source order" do
    _, body_text = macro_heredoc_fixture_parse("macro_multiple.cr")

    body_text.should contain("select_number(<<-FIRST, <<-SECOND, 65)")
    body_text.split("first payload").size.should eq(2)
    body_text.split("second payload").size.should eq(2)
    body_text.index("first payload").not_nil!.should be < body_text.index("second payload").not_nil!
  end

  it "preserves the stock opener-tail block and its inner end" do
    _, body_text = macro_heredoc_fixture_parse("macro_tail_block.cr")

    body_text.should contain("each_code(<<-BODY) do |code|")
    body_text.should contain("LibC.putchar(code)")
    body_text.split("payload").size.should eq(2)
    body_text.should contain("end")
  end

  it "expands a stock macro expression embedded in a heredoc body once" do
    program, body_text = macro_heredoc_fixture_parse("macro_body_directive.cr")
    body = macro_heredoc_literal(program)

    body.pieces.count { |piece| piece.kind == MacroHeredocSourceSliceFrontend::MacroPiece::Kind::Expression }.should eq(1)
    body_text.should_not contain("{{")
  end

  it "parses a stock macro expression in a heredoc opener tail once" do
    program, body_text = macro_heredoc_fixture_parse("macro_tail_directive.cr")
    body = macro_heredoc_literal(program)

    body.pieces.count { |piece| piece.kind == MacroHeredocSourceSliceFrontend::MacroPiece::Kind::Expression }.should eq(1)
    body_text.should_not contain("{{")
    body_text.split("payload").size.should eq(2)
  end

  it "does not publish a stock macro-control heredoc body as template text" do
    program, body_text = macro_heredoc_fixture_parse("macro_control_body.cr")
    body = macro_heredoc_literal(program)

    body.pieces.count { |piece| piece.kind == MacroHeredocSourceSliceFrontend::MacroPiece::Kind::Expression }.should eq(1)
    body_text.should_not contain("control payload")
  end

  it "rejects a bare carriage return instead of accepting it as horizontal whitespace" do
    diagnostics = [] of MacroHeredocSourceSliceFrontend::Diagnostic
    lexer = MacroHeredocSourceSliceFrontend::Lexer.new("left\rright", diagnostics: diagnostics)
    lexer.each_token { |_| }

    diagnostics.map(&.message).should contain("expected '\\n' after '\\r'")
  end
end
