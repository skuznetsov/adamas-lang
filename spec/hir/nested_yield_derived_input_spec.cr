require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  # Query a registered source Def/Arena through the normal pre-lowering yield
  # inference path. No class or method body is lowered by this test seam.
  def __test_nested_registered_source_yield_type_names(
    base_method_name : String,
    receiver_name : String,
    arg_type_names : Array(String) = [] of String,
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

    arg_types = arg_type_names.map { |name| type_ref_for_name(name) }
    # Parse a real positional call shape for this pre-lowering API query.
    query_source = "entry_probe(#{arg_types.each_index.map { |index| "input_#{index}" }.join(", ")}) {}"
    query_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(query_source))
    query = query_parser.parse_program
    raise query_parser.diagnostics.inspect unless query_parser.diagnostics.empty?
    call = query.arena[query.roots.last].as(Adamas::Compiler::Frontend::CallNode)
    inferred = block_param_types_for_call(
      registered_name,
      base_method_name,
      type_ref_for_name(receiver_name),
      arg_types,
      call_node: call,
      call_arena: query.arena,
    )
    inferred.try &.map { |type_ref| get_type_name_from_ref(type_ref) }
  end
end

private def parse_nested_yield_derived_source(source : String) : Adamas::HIR::AstToHir
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
    if node = program.arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end
  converter
end

describe "nested yield inference from derived pointer locals" do
  it "retains a direct alias of the typed pointer formal" do
    converter = parse_nested_yield_derived_source(<<-CRYSTAL)
      class NestedYieldPointerAliasOwner
        def source(value : Void*, &)
          yield value
        end

        def project(seed : Void*, &)
          original = seed
          source(seed) do |address|
            yield original
          end
        end
      end
    CRYSTAL

    converter.__test_nested_registered_source_yield_type_names(
      "NestedYieldPointerAliasOwner#project",
      "NestedYieldPointerAliasOwner",
      ["Pointer(Void)"],
    ).should eq(["Pointer(Void)"])
  end

  it "retains the captured formal type when the formal is reassigned in the nested block" do
    converter = parse_nested_yield_derived_source(<<-CRYSTAL)
      class NestedYieldPointerReassignedOwner
        def source(value : Void*, &)
          yield value
        end

        def project(seed : Void*, &)
          original = seed
          source(seed) do |address|
            seed -= 1
            yield original
          end
        end
      end
    CRYSTAL

    converter.__test_nested_registered_source_yield_type_names(
      "NestedYieldPointerReassignedOwner#project",
      "NestedYieldPointerReassignedOwner",
      ["Pointer(Void)"],
    ).should eq(["Pointer(Void)"])
  end

  it "infers the pointer difference from a captured local and nested yield input" do
    converter = parse_nested_yield_derived_source(<<-CRYSTAL)
      class NestedYieldPointerDifferenceOwner
        def source(value : Void*, &)
          yield value
        end

        def project(seed : Void*, &)
          original = seed
          while true
            source(seed) do |address|
              offset = original - address
              if offset == 0
                seed -= 1
                true
              else
                return yield offset
              end
            end
            break
          end
        end
      end
    CRYSTAL

    converter.__test_nested_registered_source_yield_type_names(
      "NestedYieldPointerDifferenceOwner#project",
      "NestedYieldPointerDifferenceOwner",
      ["Pointer(Void)"],
    ).should eq(["Int64"])
  end

  it "uses the concrete call argument for an untyped captured formal" do
    converter = parse_nested_yield_derived_source(<<-CRYSTAL)
      class NestedYieldUntypedPointerOwner
        def source(value : Void*, &)
          yield value
        end

        def project(seed, &)
          original = seed
          source(seed) do |address|
            seed -= 1
            yield original
          end
        end
      end
    CRYSTAL

    converter.__test_nested_registered_source_yield_type_names(
      "NestedYieldUntypedPointerOwner#project",
      "NestedYieldUntypedPointerOwner",
      ["Pointer(Void)"],
    ).should eq(["Pointer(Void)"])
  end
end
