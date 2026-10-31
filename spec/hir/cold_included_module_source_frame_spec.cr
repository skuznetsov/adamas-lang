require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_cold_included_source_frame(name : String) : {String?, Hash(String, String)}
    {
      function_namespace_override_for(name),
      (function_type_param_map_for_name(name) || {} of String => String).dup,
    }
  end

  def __test_cold_included_materialize(name : String) : Nil
    # Deliberately bypass lower_call: pending demand discovery also reaches
    # this API without first preparing a selected call's declaration frame.
    __test_cold_included_diagnostic(name) if ENV["DEBUG_COLD_SOURCE_FRAME"]?
    lower_function_if_needed(name)
  ensure
    if ENV["DEBUG_COLD_SOURCE_FRAME"]?
      origin = __test_cold_included_origin(name)
      witness = origin.try { |found| {found[2], found[0].object_id, found[1].object_id} }
      location = @module.function_by_name(name).try(&.definition_location)
      STDERR.puts "[COLD_SOURCE_AFTER] name=#{name} frame=#{__test_cold_included_source_frame(name)} witness=#{witness} location=#{location}"
    end
  end

  def __test_cold_included_origin(name : String)
    parts = parse_method_name_compact(name)
    find_included_module_def_origin_for_owner(
      parts.owner, parts.method.not_nil!, 0, false,
      respect_direct_declarations: false,
    )
  end

  def __test_cold_included_type_name(type : TypeRef) : String
    get_type_name_from_ref(type)
  end

  def __test_cold_included_module_formals(name : String) : Array(String)
    declared_module_type_param_names(name)
  end

  def __test_cold_projected_source_map(
    receiver_name : String,
    source_owner : String,
    formals : Array(String),
    ambient : Hash(String, String) = {} of String => String,
  ) : Hash(String, String)?
    with_isolated_type_param_map(ambient) do
      source_included_module_type_param_map(receiver_name, strip_generic_args(source_owner), formals)
    end.try(&.dup)
  end

  def __test_cold_included_module_declarations(name : String)
    (@module_defs[name]? || [] of {Adamas::Compiler::Frontend::ModuleNode, Adamas::Compiler::Frontend::ArenaLike}).dup
  end

  def __test_cold_included_diagnostic(name : String) : Nil
    owner = parse_method_name_compact(name).owner
    base = strip_generic_args(owner)
    exact_includes = @class_include_instantiations[owner]?.try(&.dup)
    base_includes = @class_include_instantiations[base]?.try(&.dup)
    # Capture the direct publication before source projection reads any aliases.
    before_map = included_module_type_param_map(owner, "ColdSourceLeaf").try(&.dup)
    projections = source_generic_ancestor_projections(owner)
    after_map = included_module_type_param_map(owner, "ColdSourceLeaf").try(&.dup)
    STDERR.puts "[COLD_SOURCE_BEFORE] name=#{name} exact=#{exact_includes} base=#{base_includes} map_before=#{before_map} projections=#{projections} map_after=#{after_map}"
  end
end

private def cold_included_module_source_fixture(annotated : Bool, bare_reopening : Bool = false)
  leaf_source = <<-CRYSTAL
    module ColdSourceLeaf(T)
      def chosen
        65u8
      end
    end
    CRYSTAL
  leaf_source = leaf_source.sub("def chosen", "def chosen : T") if annotated
  receiver_source = <<-CRYSTAL
    module ColdSourceMiddle(U)
      include ColdSourceLeaf(U)
    end

    struct Tuple
      include ColdSourceMiddle(Union(*T))
    end

    {65u8, 66}
    CRYSTAL
  decoy_source = <<-CRYSTAL
    module ColdSourceDecoy
      module ColdSourceLeaf(T)
        def chosen
          90u8
        end
      end
    end
    CRYSTAL

  leaf_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(leaf_source),
  )
  leaf_program = leaf_parser.parse_program
  leaf_parser.diagnostics.should be_empty
  receiver_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(receiver_source),
  )
  receiver_program = receiver_parser.parse_program
  receiver_parser.diagnostics.should be_empty
  decoy_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(decoy_source),
  )
  decoy_program = decoy_parser.parse_program
  decoy_parser.diagnostics.should be_empty
  leaf_arena = leaf_program.arena
  receiver_arena = receiver_program.arena
  decoy_arena = decoy_program.arena
  leaf_path = "/tmp/cold_included_module_source_leaf.cr"
  sources = {
    leaf_arena.object_id.to_u64     => leaf_source,
    receiver_arena.object_id.to_u64 => receiver_source,
    decoy_arena.object_id.to_u64    => decoy_source,
  }
  paths = {
    leaf_arena.object_id.to_u64     => leaf_path,
    receiver_arena.object_id.to_u64 => "/tmp/cold_included_module_source_receiver.cr",
    decoy_arena.object_id.to_u64    => "/tmp/cold_included_module_source_decoy.cr",
  }
  reopening_program = if bare_reopening
                        reopening_source = <<-CRYSTAL
                          module ColdSourceLeaf
                            def reopened_marker : Int32
                              90
                            end
                          end
                          CRYSTAL
                        reopening_parser = Adamas::Compiler::Frontend::Parser.new(
                          Adamas::Compiler::Frontend::Lexer.new(reopening_source),
                        )
                        parsed = reopening_parser.parse_program
                        reopening_parser.diagnostics.should be_empty
                        reopening_arena_id = parsed.arena.object_id.to_u64
                        sources[reopening_arena_id] = reopening_source
                        paths[reopening_arena_id] = "/tmp/cold_included_module_source_reopening.cr"
                        parsed
                      end
  converter = Adamas::HIR::AstToHir.new(
    leaf_arena,
    sources_by_arena: sources,
    paths_by_arena: paths,
    main_arenas: [receiver_arena] of Adamas::Compiler::Frontend::ArenaLike,
  )
  converter.no_prelude = true
  leaf = leaf_arena[leaf_program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
  definition = leaf.body.not_nil!.compact_map do |id|
    leaf_arena[id].as?(Adamas::Compiler::Frontend::DefNode)
  end.first
  converter.register_module(leaf)
  converter.arena = decoy_arena
  decoy_program.roots.each do |id|
    converter.register_module(decoy_arena[id].as(Adamas::Compiler::Frontend::ModuleNode))
  end
  if reopening_program
    converter.arena = reopening_program.arena
    reopening_program.roots.each do |id|
      converter.register_module(reopening_program.arena[id].as(Adamas::Compiler::Frontend::ModuleNode))
    end
  end

  converter.arena = receiver_arena
  main = [] of UInt64
  receiver_program.roots.each do |id|
    case node = receiver_arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    else
      main << id.index.to_u64
    end
  end
  # Instantiate the real Tuple carrier, but never call or preselect chosen.
  converter.lower_main(main)
  {converter, definition, leaf_arena, leaf_path}
end

describe "cold included-module source frames" do
  it "retains the leaf declaration frame when a Tuple body is demanded without a call" do
    converter, definition, leaf_arena, leaf_path = cold_included_module_source_fixture(false)
    name = "Tuple(UInt8, Int32)#chosen"

    converter.__test_cold_included_materialize(name)

    function = converter.module.function_by_name(name).not_nil!
    converter.__test_cold_included_type_name(function.return_type).should eq("UInt8")
    location = function.definition_location.not_nil!
    location.path.should eq(leaf_path)
    location.line.should eq(definition.span.start_line)
    function.blocks.flat_map(&.instructions).any? do |instruction|
      instruction.is_a?(Adamas::HIR::Literal) && instruction.value == 65_i64
    end.should be_true

    # The simple included-module path materializes the body under the base
    # target. The exact generic request name is only its demand key.
    namespace, _bindings = converter.__test_cold_included_source_frame("Tuple#chosen")
    namespace.should eq("ColdSourceLeaf(T)")
    origin = converter.__test_cold_included_origin(name).not_nil!
    origin[0].should be(definition)
    origin[1].should be(leaf_arena)
    origin[2].should eq("ColdSourceLeaf")
  end

  it "resolves an annotated cold body from the derived leaf binding, not the Tuple owner" do
    converter, _, _, _ = cold_included_module_source_fixture(true)
    name = "Tuple(UInt8, Int32)#chosen"

    converter.__test_cold_included_materialize(name)

    function = converter.module.function_by_name(name).not_nil!
    converter.__test_cold_included_type_name(function.return_type)
      .split('|').map(&.strip).sort.should eq(["Int32", "UInt8"])
    namespace, _bindings = converter.__test_cold_included_source_frame("Tuple#chosen")
    namespace.should eq("ColdSourceLeaf(T)")
  end

  it "uses the selected module owner despite an ambient T and same-tail declarations in another arena" do
    converter, _, leaf_arena, _ = cold_included_module_source_fixture(false)
    receiver = "Tuple(UInt8, Int32)"

    mapping = converter.__test_cold_projected_source_map(
      receiver,
      "ColdSourceLeaf",
      ["T"],
      {"T" => "Bool"},
    ).not_nil!
    mapping["T"].split('|').map(&.strip).sort.should eq(["Int32", "UInt8"])

    converter.__test_cold_projected_source_map(
      receiver,
      "ColdSourceDecoy::ColdSourceLeaf",
      ["T"],
    ).should be_nil

    origin = converter.__test_cold_included_origin("Tuple(UInt8, Int32)#chosen").not_nil!
    origin[1].should be(leaf_arena)
    origin[2].should eq("ColdSourceLeaf")
  end

  it "fails closed when the selected source owner has conflicting include applications" do
    leaf_source = <<-CRYSTAL
      module ColdSourceLeaf(T)
        def chosen : T
          65u8
        end
      end
      module ColdSourceMiddle(U)
        include ColdSourceLeaf(U)
      end
      CRYSTAL
    receiver_source = <<-CRYSTAL
      struct ColdAmbiguousOwner(P)
        include ColdSourceMiddle(Int32)
        include ColdSourceMiddle(UInt8)
      end
      CRYSTAL
    leaf_parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(leaf_source),
    )
    leaf_program = leaf_parser.parse_program
    leaf_parser.diagnostics.should be_empty
    receiver_parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(receiver_source),
    )
    receiver_program = receiver_parser.parse_program
    receiver_parser.diagnostics.should be_empty
    leaf_arena = leaf_program.arena
    receiver_arena = receiver_program.arena
    converter = Adamas::HIR::AstToHir.new(
      leaf_arena,
      sources_by_arena: {
        leaf_arena.object_id.to_u64     => leaf_source,
        receiver_arena.object_id.to_u64 => receiver_source,
      },
      paths_by_arena: {
        leaf_arena.object_id.to_u64     => "/tmp/cold_ambiguous_leaf.cr",
        receiver_arena.object_id.to_u64 => "/tmp/cold_ambiguous_receiver.cr",
      },
      main_arenas: [receiver_arena] of Adamas::Compiler::Frontend::ArenaLike,
    )
    converter.no_prelude = true
    leaf_program.roots.each do |id|
      converter.register_module(leaf_arena[id].as(Adamas::Compiler::Frontend::ModuleNode))
    end
    converter.arena = receiver_arena
    receiver_program.roots.each do |id|
      node = receiver_arena[id]
      converter.register_class(node.as(Adamas::Compiler::Frontend::ClassNode)) if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
    end

    converter.__test_cold_projected_source_map(
      "ColdAmbiguousOwner(Int32)",
      "ColdSourceLeaf",
      ["T"],
    ).should be_nil
  end

  it "retains the selected lexical namespace for a nongeneric included method" do
    source = <<-CRYSTAL
      module ColdLexicalSpace
        alias Token = Int32

        module PlainProvider
          def chosen : Token
            65
          end
        end
      end

      alias Token = UInt8

      class ColdLexicalOwner
        include ColdLexicalSpace::PlainProvider
      end
      CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source),
    )
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => source},
      paths_by_arena: {arena.object_id.to_u64 => "/tmp/cold_nongeneric_lexical_owner.cr"},
      main_arenas: [] of Adamas::Compiler::Frontend::ArenaLike,
    )
    converter.no_prelude = true
    program.roots.each do |id|
      case node = arena[id]
      when Adamas::Compiler::Frontend::ModuleNode
        converter.register_module(node)
      when Adamas::Compiler::Frontend::ClassNode
        converter.register_class(node)
      end
    end

    name = "ColdLexicalOwner#chosen"
    converter.__test_cold_included_materialize(name)

    function = converter.module.function_by_name(name).not_nil!
    converter.__test_cold_included_type_name(function.return_type).should eq("Int32")
    namespace, bindings = converter.__test_cold_included_source_frame(name)
    namespace.should eq("ColdLexicalSpace::PlainProvider")
    bindings.should be_empty
  end

  it "retains generic formals when the bare owner key contains a later reopening in another arena" do
    converter, _, leaf_arena, _ = cold_included_module_source_fixture(false, bare_reopening: true)

    generic = converter.__test_cold_included_module_declarations("ColdSourceLeaf(T)")
    generic.should_not be_empty
    generic.all? do |node, source_arena|
      source_arena.same?(leaf_arena) && node.type_params.not_nil!.map { |name| String.new(name) } == ["T"]
    end.should be_true
    bare = converter.__test_cold_included_module_declarations("ColdSourceLeaf")
    bare.should_not be_empty
    bare.all? { |node, source_arena| node.type_params.nil? && !source_arena.same?(leaf_arena) }.should be_true

    converter.__test_cold_included_module_formals("ColdSourceLeaf").should eq(["T"])
    converter.__test_cold_included_module_formals("ColdSourceLeaf(T)").should eq(["T"])
  end

  it "materializes the generic declaration across a split-arena bare reopening without changing its source witness" do
    converter, definition, leaf_arena, leaf_path = cold_included_module_source_fixture(true, bare_reopening: true)
    name = "Tuple(UInt8, Int32)#chosen"

    converter.__test_cold_included_materialize(name)

    function = converter.module.function_by_name(name).not_nil!
    converter.__test_cold_included_type_name(function.return_type)
      .split('|').map(&.strip).sort.should eq(["Int32", "UInt8"])
    origin = converter.__test_cold_included_origin(name).not_nil!
    origin[0].should be(definition)
    origin[1].should be(leaf_arena)
    origin[2].should eq("ColdSourceLeaf")
    function.definition_location.not_nil!.path.should eq(leaf_path)
  end
end
