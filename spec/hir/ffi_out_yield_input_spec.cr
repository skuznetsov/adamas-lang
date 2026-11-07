require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  # Select the exact registered source declaration and ask the production
  # callback-signature inference path for its yield types. This runs after
  # source registration and before any method body is lowered.
  def __test_registered_source_yield_type_names(
    base_method_name : String,
    receiver_name : String,
  ) : Array(String)?
    registered_name = @function_defs.keys
      .select { |name| name == base_method_name || name.starts_with?("#{base_method_name}$") }
      .sort
      .first?
    return nil unless registered_name

    definition = @function_defs[registered_name]
    source_arena = @function_def_arenas[registered_name]?
    return nil unless source_arena
    return nil unless registered_arena_for_def(definition).try(&.same?(source_arena))

    inferred = block_param_types_for_call(
      registered_name,
      base_method_name,
      type_ref_for_name(receiver_name),
      [] of TypeRef,
    )
    inferred.try &.map { |type_ref| get_type_name_from_ref(type_ref) }
  end
end

private def parse_ffi_out_yield_source(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::LibNode
      converter.register_lib(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter
end

describe "FFI out locals during source yield inference" do
  source = <<-CRYSTAL
    lib FfiOutYieldSource
      struct Info
        code : Int32
        address : Void*
        bytes : UInt8**
      end
      fun populate(address : Void*, info : Info*) : Int32
    end

    class FfiOutYieldOwner
      def each(&)
        FfiOutYieldSource.populate(nil, out info)
        yield info, info.code, info.address, info.bytes
      end
    end
  CRYSTAL

  it "infers the out local and its struct fields before lowering the method" do
    converter = parse_ffi_out_yield_source(source)
    converter.__test_registered_source_yield_type_names(
      "FfiOutYieldOwner#each",
      "FfiOutYieldOwner",
    ).should eq([
      "FfiOutYieldSource::Info",
      "Int32",
      "Pointer(Void)",
      "Pointer(Pointer(UInt8))",
    ])
    # The test seam only performs source registration and inference. A lowered
    # HIR function would make this a late-lowering test instead.
    converter.module.has_function?("FfiOutYieldOwner#each").should be_false
  end
end
