require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias ScopedAliasFrontend = Adamas::Compiler::Frontend
alias ScopedAliasSemantic = Adamas::Compiler::Semantic

private def infer_scoped_alias_source(source : String)
  lexer = ScopedAliasFrontend::Lexer.new(source)
  parser = ScopedAliasFrontend::Parser.new(lexer)
  program = parser.parse_program

  analyzer = ScopedAliasSemantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe ScopedAliasSemantic::TypeInferenceEngine do
  it "resolves scoped aliases through lexical alias heads" do
    source = <<-CRYSTAL
    module DiamondFoundation
      module Storage
        class ClusterBackupPlan
          class Replica
          end

          enum ReplicaState
            Serving
          end

          class Partition
          end

          class PersistedBackup
          end
        end
      end
    end

    module DiamondCLI
      module S3RestoreSmoke
        private alias Plan = DiamondFoundation::Storage::ClusterBackupPlan
        private alias Replica = Plan::Replica
        private alias ReplicaState = Plan::ReplicaState

        def self.build : {Plan::Partition, Plan::PersistedBackup}
          replica = Replica.new
          state = ReplicaState::Serving
          {Plan::Partition.new, Plan::PersistedBackup.new}
        end
      end
    end
    CRYSTAL

    _program, _analyzer, engine = infer_scoped_alias_source(source)

    inferred_names = engine.context.expression_types.values.map(&.to_s)
    inferred_names.should contain("Replica")
    inferred_names.should contain("ReplicaState")
    inferred_names.should contain("Tuple(Partition, PersistedBackup)")
  end
end
