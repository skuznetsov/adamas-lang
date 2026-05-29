require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

private def infer_eager_assignment_scope_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

private def find_identifier_expr_id(program : Frontend::Program, name : String, line : Int32, column : Int32? = nil) : Frontend::ExprId
  arena = program.ast_arena

  arena.size.times do |i|
    expr_id = Frontend::ExprId.new(i)
    node = arena[expr_id]
    next unless node.is_a?(Frontend::IdentifierNode)
    next unless String.new(node.name) == name
    span = node.span
    next unless span.start_line == line
    return expr_id if column.nil? || span.start_column == column
  end

  raise "identifier #{name}@#{line}:#{column || "*"} not found"
end

describe Semantic::TypeInferenceEngine do
  describe "eager method body assignment scope" do
    it "does not leak local assignments across sibling defs" do
      source = <<-CRYSTAL
        module LeakPlain
          def self.seed
            value = 1 == 0 ? "x" : nil
            value
          end

          def self.use(value : Int32)
            other = value
            value + 1
          end
        end

        1
      CRYSTAL

      program, analyzer, engine = infer_eager_assignment_scope_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "does not leak nested callee locals back into caller locals" do
      source = <<-CRYSTAL
        module LeakNested
          def self.helper(value : UInt32)
            r = value.to_u64
            r
          end

          def self.run(value : UInt32)
            r = value
            helper(value)
            r
          end
        end

        LeakNested.run(1_u32)
      CRYSTAL

      program, analyzer, engine = infer_eager_assignment_scope_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.select(&.level.error?).should be_empty

      caller_r = find_identifier_expr_id(program, "r", 10)
      engine.context.get_type(caller_r).to_s.should eq("UInt32")
      engine.context.get_type(program.roots.last).to_s.should eq("UInt32")
    end
  end
end
