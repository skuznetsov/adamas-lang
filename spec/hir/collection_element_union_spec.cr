require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_collection_element_type(name : String) : String?
    element_type_for_type_name(name)
  end

  def __test_type_name(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end

  def __test_infer_expr_type_name(
    expr_id : Adamas::Compiler::Frontend::ExprId,
    local_name : String,
    local_type_name : String,
  ) : String?
    old_locals = @current_typeof_locals
    old_names = @current_typeof_local_names
    @current_typeof_locals = {local_name => type_ref_for_name(local_type_name)}
    @current_typeof_local_names = {local_name => local_type_name}
    begin
      inferred = infer_type_from_expr(expr_id, nil)
      inferred ? get_type_name_from_ref(inferred) : nil
    ensure
      @current_typeof_locals = old_locals
      @current_typeof_local_names = old_names
    end
  end
end

private def collection_union_parse(
  code : String,
) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

private def lower_collection_index_program(
  code : String,
  name : String,
) : {Adamas::HIR::AstToHir, Adamas::HIR::Function}
  arena, exprs = collection_union_parse(code)
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => code},
  )
  converter.arena = arena

  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  exprs.each do |expr_id|
    case node = arena[expr_id]
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    end
  end

  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }
  class_nodes.each { |node| converter.lower_class(node) }

  target = def_nodes.find { |node| String.new(node.name) == name }
  raise "function #{name} not found" unless target
  {converter, converter.lower_def(target)}
end

private def first_index_get(function : Adamas::HIR::Function) : Adamas::HIR::IndexGet
  function.blocks.each do |block|
    block.instructions.each do |instruction|
      return instruction if instruction.is_a?(Adamas::HIR::IndexGet)
    end
  end
  raise "IndexGet not found in #{function.name}"
end

private def last_body_expr_id(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  roots : Array(Adamas::Compiler::Frontend::ExprId),
  name : String,
) : Adamas::Compiler::Frontend::ExprId
  target = roots.compact_map do |expr_id|
    node = arena[expr_id]
    node if node.is_a?(Adamas::Compiler::Frontend::DefNode) && String.new(node.name) == name
  end.first?
  raise "function #{name} not found" unless target
  body = target.body
  raise "function #{name} has no body" unless body
  body.last
end

private def lower_collection_macro_program(code : String) : Adamas::HIR::AstToHir
  arena, exprs = collection_union_parse(code)
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => code},
  )
  converter.arena = arena

  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  main_exprs = [] of UInt64

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs) unless main_exprs.empty?
  converter
end

private def with_collection_inline_yield_disabled(& : -> Adamas::HIR::AstToHir)
  previous = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
  ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
  yield
ensure
  if previous
    ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous
  else
    ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
  end
end

private def collection_macro_block_proc(
  converter : Adamas::HIR::AstToHir,
  names : Array(String),
) : Adamas::HIR::Function
  matches = converter.module.functions.select do |function|
    function.name.starts_with?("__crystal_block_proc_") && function.params.map(&.name) == names
  end
  raise "expected one block proc #{names.inspect}, got #{matches.map(&.name).inspect}" unless matches.size == 1
  matches.first
end

private def collection_macro_yield_source : String
  <<-CRYSTAL
    module Enumerable(T)
    end

    class OtherPart
    end

    class Path
      def initialize
      end

      def consume(part : Int32) : Path
        self
      end

      def probe(parts : Tuple(OtherPart | Path, Int32)) : Path
        parts.yield_second { |part| consume(part) }
      end
    end

    struct Tuple
      include Enumerable(Union(*T))

      def yield_second(&)
        yield self[1]
      end
    end

    class Thread
      def join : Nil
        nil
      end
    end

    Path.new.probe({OtherPart.new, 1})
  CRYSTAL
end

private def collection_macro_yield_type_names(
  converter : Adamas::HIR::AstToHir,
  names : Array(String),
) : Array(String)
  function = collection_macro_block_proc(converter, names)
  function.params.map { |param| converter.__test_type_name(param.type) }
end

describe "collection element union extraction" do
  it "unwraps a top-level union of collection owners" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_collection_element_type("Array(Int32) | Slice(String)").should eq("Int32 | String")
  end

  it "keeps a union nested in an Array argument" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_collection_element_type("Array(Int32 | String)").should eq("Int32 | String")
  end

  it "keeps a union nested in a Tuple argument" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_collection_element_type("Tuple(Int32 | String, Bool)").should eq("Int32 | String | Bool")
  end

  it "keeps heterogeneous tuple arguments as a control" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_collection_element_type("Tuple(Int32, String)").should eq("Int32 | String")
  end

  it "propagates a nested tuple union through IndexNode HIR" do
    converter, function = lower_collection_index_program(<<-CRYSTAL, "probe")
      class OtherPart
      end

      class Path
      end

      def probe(parts : Tuple(OtherPart | Path, Int32))
        parts[0]
      end
    CRYSTAL

    index_get = first_index_get(function)
    converter.__test_type_name(index_get.type).should eq("OtherPart | Path")
    converter.__test_type_name(function.return_type).should eq("OtherPart | Path")
    index_get.type.should eq(function.return_type)
    function.return_type.should_not eq(Adamas::HIR::TypeRef::VOID)
  end

  it "preserves the literal tuple position during expression inference" do
    code = <<-CRYSTAL
      def probe(parts : Tuple(OtherPart | Path, Int32))
        parts[1]
      end
    CRYSTAL
    arena, roots = collection_union_parse(code)
    converter = Adamas::HIR::AstToHir.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => code},
    )
    converter.arena = arena

    index_id = last_body_expr_id(arena, roots, "probe")
    converter.__test_infer_expr_type_name(
      index_id,
      "parts",
      "Tuple(OtherPart | Path, Int32)",
    ).should eq("Int32")
  end

  it "preserves a class union in a homogeneous tuple at a literal position" do
    code = <<-CRYSTAL
      def probe(parts : Tuple(OtherPart | Path, OtherPart | Path))
        parts[1]
      end
    CRYSTAL
    arena, roots = collection_union_parse(code)
    converter = Adamas::HIR::AstToHir.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => code},
    )
    converter.arena = arena

    index_id = last_body_expr_id(arena, roots, "probe")
    converter.__test_infer_expr_type_name(
      index_id,
      "parts",
      "Tuple(OtherPart | Path, OtherPart | Path)",
    ).should eq("OtherPart | Path")
  end

  it "preserves a literal tuple position through a nilable receiver" do
    code = <<-CRYSTAL
      def probe(parts : Tuple(OtherPart | Path, Int32) | Nil)
        parts[1]
      end
    CRYSTAL
    arena, roots = collection_union_parse(code)
    converter = Adamas::HIR::AstToHir.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => code},
    )
    converter.arena = arena

    index_id = last_body_expr_id(arena, roots, "probe")
    converter.__test_infer_expr_type_name(
      index_id,
      "parts",
      "Tuple(OtherPart | Path, Int32) | Nil",
    ).should eq("Int32")
  end

  it "keeps the first member of a nilable DefNode and ArenaLike result" do
    code = <<-CRYSTAL
      def probe(found : Tuple(Adamas::Compiler::Frontend::DefNode, Adamas::Compiler::Frontend::ArenaLike) | Nil)
        found[0]
      end
    CRYSTAL
    arena, roots = collection_union_parse(code)
    converter = Adamas::HIR::AstToHir.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => code},
    )
    converter.arena = arena

    index_id = last_body_expr_id(arena, roots, "probe")
    converter.__test_infer_expr_type_name(
      index_id,
      "found",
      "Tuple(Adamas::Compiler::Frontend::DefNode, Adamas::Compiler::Frontend::ArenaLike) | Nil",
    ).should eq("Adamas::Compiler::Frontend::DefNode")
  end

  it "keeps non-Tuple union arms in the collection fallback" do
    code = <<-CRYSTAL
      def probe(parts : Tuple(Int32, String) | Array(Bool) | Nil)
        parts[1]
      end
    CRYSTAL
    arena, roots = collection_union_parse(code)
    converter = Adamas::HIR::AstToHir.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => code},
    )
    converter.arena = arena

    index_id = last_body_expr_id(arena, roots, "probe")
    converter.__test_infer_expr_type_name(
      index_id,
      "parts",
      "Tuple(Int32, String) | Array(Bool) | Nil",
    ).should eq("Bool | Int32 | String")
  end

  it "keeps dynamic and out-of-range tuple indexes conservative" do
    [
      {"parts[index]", "Tuple(Int32, String), index : Int32", "Tuple(Int32, String)"},
      {"parts[2]", "Tuple(Int32, String)", "Tuple(Int32, String)"},
      {"parts[0]", "Tuple(Int32) | Tuple(String)", "Tuple(Int32) | Tuple(String)"},
    ].each do |expression, params, local_type|
      code = "def probe(parts : #{params})\n  #{expression}\nend\n"
      arena, roots = collection_union_parse(code)
      converter = Adamas::HIR::AstToHir.new(
        arena,
        sources_by_arena: {arena.object_id.to_u64 => code},
      )
      converter.arena = arena

      index_id = last_body_expr_id(arena, roots, "probe")
      converter.__test_infer_expr_type_name(index_id, "parts", local_type).should eq("Int32 | String")
    end
  end

  it "uses the literal tuple position for a macro-generated yield parameter" do
    converter = with_collection_inline_yield_disabled do
      lower_collection_macro_program(collection_macro_yield_source)
    end

    collection_macro_yield_type_names(converter, ["part"]).should eq(["Int32"])
  end
end

describe "Tuple position inference boundary" do
  it "does not mistake union variants for tuple positions" do
    code = <<-CRYSTAL
      def probe(parts : Tuple(Int32) | Tuple(Bool))
        parts[0]
      end
    CRYSTAL
    arena, roots = collection_union_parse(code)
    converter = Adamas::HIR::AstToHir.new(
      arena, sources_by_arena: {arena.object_id.to_u64 => code},
    )
    converter.arena = arena
    inferred = converter.__test_infer_expr_type_name(
      last_body_expr_id(arena, roots, "probe"),
      "parts", "Tuple(Int32) | Tuple(Bool)",
    )
    inferred.not_nil!.split(" | ").sort.should eq(["Bool", "Int32"])
  end
end
