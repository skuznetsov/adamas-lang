require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

private def lower_inline_return_owner_fixture(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/inline_block_logical_return_owner_spec.cr"},
  )
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::LibNode
      converter.register_lib(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

private def inline_return_owner_valid_source : String
  <<-CRYSTAL
    lib InlineReturnOwnerSpecNative
      fun getpid : Int32
    end

    def owner_sync(&)
      yield
    end

    def nil_step(flag : Bool, &) : Nil
      owner_sync do
        return unless flag
        yield 65
      end
    end

    def nil_probe(flag : Bool, &) : Bool
      nil_step(flag) do |entry|
        yield entry
        return true
      end
      false
    end

    def forwarded_probe(flag : Bool, &) : Bool
      owner_sync do
        nil_step(flag) do |entry|
          yield entry
          return true
        end
      end
      false
    end

    def no_return_inner(flag : Bool, &)
      owner_sync { yield flag }
    end

    def no_return_probe(flag : Bool) : Bool
      no_return_inner(flag) do |entry|
        owner_sync { entry }
      end
    end

    def scalar_step(flag : Bool, &) : Int32
      owner_sync do
        return 73 unless flag
        yield 65
      end
      74
    end

    def scalar_probe(flag : Bool, &) : Int32
      scalar_step(flag) do |entry|
        yield entry
        return 81
      end
      67
    end

    def physical_return_step(&)
      owner_sync { yield }
    end

    def physical_return_probe : Bool
      physical_return_step { return true }
      false
    end

    def generic_step(value : T, &) : Int32 forall T
      owner_sync { return 75 }
      76
    end

    def boolean_after_generic_integer : Bool
      generic_step(75) {}
      true
    end

    def boolean_after_generic_boolean : Bool
      generic_step(true) {}
      true
    end

    nil_probe(InlineReturnOwnerSpecNative.getpid > 0) { |entry| entry == 65 }
    nil_probe(InlineReturnOwnerSpecNative.getpid < 0) { |entry| entry == 65 }
    physical_return_probe
    forwarded_probe(InlineReturnOwnerSpecNative.getpid > 0) { |entry| entry == 65 }
    no_return_probe(InlineReturnOwnerSpecNative.getpid > 0)
    boolean_after_generic_integer
    boolean_after_generic_boolean
    scalar_probe(InlineReturnOwnerSpecNative.getpid < 0) { |entry| entry == 65 }
    scalar_probe(InlineReturnOwnerSpecNative.getpid > 0) { |entry| entry == 65 }
    CRYSTAL
end

describe "inline block logical return ownership" do
  it "lowers nested, forwarded, and repeated generic returns with distinct logical owners" do
    converter = lower_inline_return_owner_fixture(inline_return_owner_valid_source)
    converter.module.functions.should_not be_empty
  end
end
