require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_materialize_inline_lexical_context : Nil
    process_pending_lower_functions
  end
end

private def lower_inline_lexical_context(source : String)
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
    else
      expressions << id.index.to_u64
    end
  end
  converter.lower_main(expressions)
  converter.__test_materialize_inline_lexical_context
  converter
end

private def inline_lexical_context_source(callee_body : String, caller_block : String, callee_mixin : Bool = false)
  yielding_method = <<-CRYSTAL
    def yield_then_answer(&) : Int32
      yield
      #{callee_body}
    end
  CRYSTAL
  yielding_module = callee_mixin ? "module YieldingMethods\n#{yielding_method}\nend" : ""
  class_body = callee_mixin ? "include YieldingMethods" : yielding_method
  <<-CRYSTAL
    module Guarded
      #{yielding_module}
      class Context
        protected def answer : Int32
          42
        end
        #{class_body}
      end
    end
    module Unrelated
      module Methods
        def via_mixin : Int32
          Guarded::Context.new.yield_then_answer do
            #{caller_block}
          end
        end
      end
      class Caller
        include Methods
      end
    end
    Unrelated::Caller.new.via_mixin
  CRYSTAL
end

describe "inline yield lexical context ownership" do
  it "clears an unrelated caller override while lowering the inline callee" do
    lower_inline_lexical_context(inline_lexical_context_source("Guarded::Context.new.answer", "1"))
  end

  it "retains a non-nil lexical override owned by the inline callee" do
    lower_inline_lexical_context(inline_lexical_context_source("Guarded::Context.new.answer", "1", callee_mixin: true))
  end

  it "restores the caller override for the caller-owned yielded block" do
    source = inline_lexical_context_source("42", "Guarded::Context.new.answer")
    expect_raises(Adamas::HIR::LoweringError, /protected method 'answer'/) do
      lower_inline_lexical_context(source)
    end
  end
end
