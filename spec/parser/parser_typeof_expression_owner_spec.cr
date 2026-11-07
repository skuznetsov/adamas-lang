require "spec"
require "compiler/crystal/syntax"
require "../../src/compiler/frontend/parser"

private def typeof_source_parser(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  {parser, program}
end

TYPEOF_PAYLOADS = [
  "@config.amqp_port", "@@current", "true", "nil", "'a'",
  "/abc/", "[1, 2]", "{1, 2}", "owner.map { |item| item }",
  "value = 65", "typeof(@config.amqp_port)", "1, 2,", "\n@config.amqp_port,\ntrue,\n",
]
TYPEOF_CONTEXTS = [
  {"expression", "typeof(%s)"},
  {"proc parameter", "->(arg : typeof(%s)) { arg }"},
  {"declaration", "value : typeof(%s)"},
  {"structural type", "value.is_a?(typeof(%s))"},
  {"generic type", "Box(typeof(%s))"},
]

describe "Typeof payload grammar belongs to expression parsing" do
  TYPEOF_CONTEXTS.each do |context, format|
    TYPEOF_PAYLOADS.each do |payload|
      it "preserves #{payload.inspect} in #{context}" do
        source = format % payload
        Crystal::Parser.parse(source)
        parser, program = typeof_source_parser(source)
        parser.diagnostics.should be_empty
        program.roots.size.should eq(1)
        if context == "proc parameter"
          proc_node = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::ProcLiteralNode)
          proc_node.params.not_nil!.size.should eq(1)
          String.new(proc_node.params.not_nil!.first.type_annotation.not_nil!).should eq("typeof(#{payload})")
        end
      end
    end
  end

  ["", "65 66", "65,,66", "@config.", "@config.amqp_port +", "@config.amqp_port =", "1 ? 2", "1 +", "1 |", "1 =="].each do |payload|
    TYPEOF_CONTEXTS.each do |context, format|
      it "rejects #{payload.inspect} in #{context}" do
        source = format % payload
        expect_raises(Crystal::SyntaxException) { Crystal::Parser.parse(source) }
        parser, _ = typeof_source_parser(source)
        parser.diagnostics.should_not be_empty
      end
    end
  end
end


describe "Typeof delimiter ownership" do
  [
    "->(arg : typeof(\n@config.amqp_port,\ntrue,\n), tail : Int32) { tail }\nafter = 1",
    "Box(typeof(@config.amqp_port), typeof(true))\nafter = 1",
    "value : typeof(@config.amqp_port)?\nafter = 1",
    "value.is_a?(typeof(typeof(@config.amqp_port)))\nafter = 1",
  ].each do |source|
    it "preserves the following owner in #{source.inspect}" do
      Crystal::Parser.parse(source)
      parser, program = typeof_source_parser(source)
      parser.diagnostics.should be_empty
      program.roots.size.should eq(2)
    end
  end

  ["typeof", "typeof 1", "typeof(1", "->(arg : typeof(1 +)) { arg }"].each do |source|
    it "keeps a primary diagnostic for #{source.inspect}" do
      expect_raises(Crystal::SyntaxException) { Crystal::Parser.parse(source) }
      parser, _ = typeof_source_parser(source)
      parser.diagnostics.should_not be_empty
    end
  end
end


describe "Generic typeof suffix ownership" do
  ["Box(typeof(1)?)", "Box(typeof(1)*)", "Box(typeof(1)**)",
   "Box(typeof(1)[2])", "Box(typeof(1).class)", "Box(typeof(1) | Nil)",
   "Box({typeof(1), Bool})", "Box(typeof(@config.port)?, Bool)"].each do |source|
    it "keeps the type suffix in #{source.inspect}" do
      Crystal::Parser.parse(source)
      parser, program = typeof_source_parser(source)
      parser.diagnostics.should be_empty
      program.roots.size.should eq(1)
      generic = program.arena[program.roots.first]
      args = Adamas::Compiler::Frontend.node_generic_type_args(generic).not_nil!
      actual = args.map do |arg|
        String.new(Adamas::Compiler::Frontend.node_literal(program.arena[arg]).not_nil!).gsub(/\s+/, "")
      end
      expected = if source == "Box(typeof(@config.port)?, Bool)"
                   ["typeof(@config.port)?", "Bool"]
                 else
                   [source.byte_slice(4, source.bytesize - 5).gsub(/\s+/, "")]
                 end
      actual.should eq(expected)
    end
  end
  ["Box(typeof(1 +)?)", "Box(typeof(1 2).class)"].each do |source|
    it "retains payload diagnostics before suffixes in #{source.inspect}" do
      expect_raises(Crystal::SyntaxException) { Crystal::Parser.parse(source) }
      parser, _ = typeof_source_parser(source)
      parser.diagnostics.should_not be_empty
    end
  end
end
