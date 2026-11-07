require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_instance_fixed_arity_program(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true

  main = [] of UInt64
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "source fixed-arity instance call admission" do
  it "rejects an extra positional argument after exact source lookup fails" do
    expect_raises(Adamas::HIR::LoweringError, "no overload matches 'UInt64#value_self_contract'") do
      lower_instance_fixed_arity_program(<<-CRYSTAL)
        class Object
          def value_self_contract : UInt64
            value_self_contract(65_u64)
          end
        end

        struct Value
        end

        struct Number
        end

        struct Int
        end

        struct UInt64
          def value_self_contract(item)
            item
          end
        end

        1_u64.value_self_contract(65_u64, 66_u64)
        CRYSTAL
    end
  end

  it "keeps defaults, positional rest, named-only arguments, and self redispatch admissible" do
    lower_instance_fixed_arity_program(<<-CRYSTAL)
      struct Value
      end

      struct Number
      end

      struct Int
      end

      struct UInt64
        def defaulted(first : UInt64, second : UInt64 = 66_u64) : UInt64
          first
        end

        def collected(*items : UInt64) : UInt64
          67_u64
        end

        def named_only(*, first : UInt64) : UInt64
          first
        end

        def relay(item : UInt64) : UInt64
          item
        end

        def relay : UInt64
          relay(68_u64)
        end

        def observed : UInt64
          self.relay
        end
      end

      1_u64.defaulted(65_u64)
      1_u64.collected(65_u64, 66_u64)
      1_u64.named_only(first: 65_u64)
      1_u64.observed
      CRYSTAL
  end
end
