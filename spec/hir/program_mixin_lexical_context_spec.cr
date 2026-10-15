require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_materialize_program_mixin_context : Nil
    process_pending_lower_functions
  end
end

private def lower_program_mixin_lexical_context(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    main_arenas: [arena] of Adamas::Compiler::Frontend::ArenaLike)
  expressions = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    when Adamas::Compiler::Frontend::IncludeNode, Adamas::Compiler::Frontend::ExtendNode
      converter.register_top_level_program_mixin(node.target, arena)
    else
      expressions << id.index.to_u64
    end
  end
  converter.lower_main(expressions)
  converter.__test_materialize_program_mixin_context
  converter
end

private def program_mixin_context_source(operation : String, receiver : String = "Guarded::Context")
  <<-CRYSTAL
    module Guarded
      class Context
        protected def answer : Int32
          42
        end
      end
      module Methods
        def guarded_answer : Int32
          #{receiver}.new.answer
        end
      end
    end
    #{operation} Guarded::Methods
    guarded_answer
  CRYSTAL
end

describe "Program mixin lexical context" do
  it "retains protected access from the included definition's namespace" do
    converter = lower_program_mixin_lexical_context(program_mixin_context_source("include"))
    converter.module.has_function_with_body?("guarded_answer").should be_true
  end

  it "retains protected access for a top-level extend" do
    converter = lower_program_mixin_lexical_context(program_mixin_context_source("extend"))
    converter.module.has_function_with_body?("guarded_answer").should be_true
  end

  it "resolves a relative receiver type inside the declaring module" do
    converter = lower_program_mixin_lexical_context(program_mixin_context_source("include", "Context"))
    converter.module.has_function_with_body?("guarded_answer").should be_true
  end

  it "rejects the same protected call in an unrelated imported module" do
    source = <<-CRYSTAL
      module Guarded
        class Context
          protected def answer : Int32
            42
          end
        end
      end
      module Unrelated
        def guarded_answer : Int32
          Guarded::Context.new.answer
        end
      end
      include Unrelated
      guarded_answer
    CRYSTAL
    expect_raises(Adamas::HIR::LoweringError, /protected method 'answer'/) do
      lower_program_mixin_lexical_context(source)
    end
  end

  it "keeps private methods inaccessible through an explicit receiver" do
    source = program_mixin_context_source("include").sub("protected def answer", "private def answer")
    expect_raises(Adamas::HIR::LoweringError, /private method 'answer'/) do
      lower_program_mixin_lexical_context(source)
    end
  end
end
