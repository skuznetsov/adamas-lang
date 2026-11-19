require "spec"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_sparse_positional_overload(call_ids : Array(ExprId))
    function = @module.create_function("sparse_consumer", TypeRef::VOID)
    ctx = LoweringContext.new(function, @module, @arena)
    # Model a producer whose result type will only be available on replay.
    unresolved = Literal.new(ctx.next_id, TypeRef::VOID, nil)
    ctx.emit(unresolved)
    ctx.register_local("digest", unresolved.id)

    call_ids.map do |id|
      result = lower_call(ctx, @arena[id].as(Adamas::Compiler::Frontend::CallNode), id)
      call = ctx.value_for(result).as(Call)
      target = call.method_name
      {target, @function_defs[target]?, @function_def_arenas[target]?}
    end
  end

  def __test_sparse_overload_declaration(name : String)
    @function_defs[name]
  end
end

describe "sparse positional overload selection" do
  it "keeps the inherited three-argument body when a two-argument specialization already exists" do
    source = <<-CRYSTAL
      struct Int
        def sparse_probe(entry, digest, key)
          13
        end

        def sparse_probe(entry, key)
          19
        end
      end

      7_i64.sparse_probe(1_i32, 11_i16)
      7_i64.sparse_probe(1_i32, digest, 11_i16)
      CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))

    sibling, pending = converter.__test_sparse_positional_overload(program.roots[1..])
    sibling[0].should end_with("#sparse_probe$Int32_Int16")
    pending[0].should end_with("$arity3")
    pending[1].should be(converter.__test_sparse_overload_declaration("Int#sparse_probe$arity3"))
    pending[2].should be(arena)
  end
end
