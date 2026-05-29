require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/symbol_table"
require "../../src/compiler/semantic/symbol"
require "../../src/compiler/semantic/collectors/symbol_collector"
require "../../src/compiler/semantic/resolvers/name_resolver"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/compile_shadow_aggregate"
require "../../src/compiler/semantic/types/type"
require "../../src/compiler/semantic/type_inference_engine"

module TypeInferenceSliceLiteralSpecAliases
  alias Frontend = Adamas::Compiler::Frontend
  alias Semantic = Adamas::Compiler::Semantic
end

include TypeInferenceSliceLiteralSpecAliases

private def infer_types_from_units_for_slice_literal(units : Array(NamedTuple(path: String, source: String)))
  aggregate = Semantic::CompileShadowAggregate.build(units)
  program = aggregate.program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols(
    node_file_path_provider: ->(expr_id : Frontend::ExprId) { aggregate.path_for(expr_id) },
    source_for_path_provider: ->(path : String) { aggregate.source_for_path(path) }
  )
  name_result = analyzer.resolve_names

  engine = Semantic::TypeInferenceEngine.new(program, name_result.identifier_symbols, analyzer.global_context.symbol_table)
  engine.infer_types

  {analyzer, name_result, engine}
end

describe Adamas::Compiler::Semantic::TypeInferenceEngine do
  it "infers Slice.literal constants across reopened path-style modules" do
    units = [
      {
        path: "/tmp/type_inference_slice_literal_a.cr",
        source: <<-CRYSTAL,
          struct Slice(T)
            def self.literal(*elts : T)
              elts
            end
          end

          class Float
          end

          module Float::FastFloat
            module Powers
              SMALLEST = 1
            end
          end
        CRYSTAL
      },
      {
        path: "/tmp/type_inference_slice_literal_b.cr",
        source: <<-CRYSTAL,
          module Float::FastFloat::Powers
            TABLE = Slice(UInt64).literal(1_u64, 2_u64)
          end
        CRYSTAL
      },
      {
        path: "/tmp/type_inference_slice_literal_c.cr",
        source: <<-CRYSTAL,
          module Float::FastFloat
            def self.probe
              ptr = Powers::TABLE.to_unsafe
              ptr[Powers::SMALLEST]
            end
          end
        CRYSTAL
      },
    ]

    analyzer, _name_result, engine = infer_types_from_units_for_slice_literal(units)

    analyzer.semantic_diagnostics.should be_empty
    analyzer.name_resolver_diagnostics.should be_empty
    engine.diagnostics.should be_empty
  end
end
