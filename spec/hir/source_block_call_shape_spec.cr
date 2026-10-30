require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_source_block_call_shape(
    def_node : Adamas::Compiler::Frontend::DefNode,
    arg_count : Int32,
    has_block : Bool = false,
    named_names : Array(String)? = nil,
    raw_positional_count : Int32? = nil,
    has_splat : Bool = false,
    arg_type_names : Array(String)? = nil,
  ) : Bool
    arg_types = arg_type_names.try do |names|
      names.map { |name| type_ref_for_name(name) }
    end
    input = CallResolutionInput.new(
      "SourceBlockCallShapeProbe#test",
      arg_count,
      arg_types,
      has_block,
      has_splat,
      !named_names.nil?,
      named_names,
      raw_positional_count,
    )
    call_target_matches_call_shape?(input, def_node)
  end

  def __test_generated_getter_shape(
    name : String,
    arg_count : Int32 = 0,
    has_block : Bool = false,
    has_splat : Bool = false,
    has_named : Bool = false,
  ) : Bool
    generated_class_getter_accepts_call_shape?(name, arg_count, has_block, has_splat, has_named)
  end

  # Deliberately make the name-level caches disagree with the exact Def. The
  # shape check must use the registered Def identity, not the sibling overload
  # that happens to share its source method name.
  def __test_poison_source_def_name_caches(
    exact_def : Adamas::Compiler::Frontend::DefNode,
    sibling_def : Adamas::Compiler::Frontend::DefNode,
  ) : String
    key = nil.as(String?)
    @function_defs.each do |name, registered_def|
      if registered_def.same?(exact_def) && name.includes?('$')
        key = name
        break
      end
    end
    cache_key = key || raise "exact Def has no registered mangled name"
    @function_param_stats[cache_key] = build_param_stats(sibling_def)
    @function_param_infos[cache_key] = function_param_infos(sibling_def)
    cache_key
  end
end

private def source_block_call_shape_fixture
  source = <<-CRYSTAL
    class SourceBlockCallShapeProbe
      class_getter generated : Int32
      class_getter conflicted : Int32
      def self.conflicted(value : Int32) : Int32; value; end
      def fixed(first : Int32, second : Int32); end
      def defaulted(first : Int32, second : Int32 = 0); end
      def pair(first : Int32, second : Int32 = 0); end
      def named_only(*, first : Int32, second : Int32 = 0); end
      def required_pair(first : Int32, second : Int32, *, note : Int32, &block : -> Int32); yield; end
      def tuple_splat(first : Int32, second : Int32 = 0, &block : -> Int32); yield; end
      def keyword_splat(*, first : Int32, second : Int32 = 0, &block : -> Int32); yield; end
      def explicit_block(&block); end
      def implicit_yield(value : Int32); yield value; end
      def overloaded(first : Int32); end
      def overloaded(second : String, *, option : Bool); end
    end

    class SourceBlockCallShapeChild < SourceBlockCallShapeProbe
    end

    class SourceBlockCallShapeOverride < SourceBlockCallShapeProbe
      def self.generated : Int32; 66; end
    end

    class SourceBlockCallShapeOverload < SourceBlockCallShapeProbe
      def self.generated(value : Int32) : Int32; value; end
    end
  CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  parsed = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  converter = Adamas::HIR::AstToHir.new(
    parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  converter.arena = parsed.arena

  definitions = {} of String => Array(Adamas::Compiler::Frontend::DefNode)
  parsed.roots.each do |root_id|
    next unless owner = parsed.arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
    converter.register_class(owner)
    owner.body.try &.each do |member_id|
      next unless definition = parsed.arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
      (definitions[String.new(definition.name)] ||= [] of Adamas::Compiler::Frontend::DefNode) << definition
    end
  end

  {converter, definitions}
end

describe "selected source Def call-shape admission" do
  it "admits only the declared zero-argument shape of a generated class getter" do
    converter, _ = source_block_call_shape_fixture
    name = "SourceBlockCallShapeProbe.generated"
    converter.__test_generated_getter_shape(name).should be_true
    converter.__test_generated_getter_shape(name, 1).should be_false
    converter.__test_generated_getter_shape(name, has_block: true).should be_false
    converter.__test_generated_getter_shape(name, has_splat: true).should be_false
    converter.__test_generated_getter_shape(name, has_named: true).should be_false
    converter.__test_generated_getter_shape("SourceBlockCallShapeProbe.missing").should be_false
  end

  it "retains a getter beside nonconflicting source Def overloads" do
    converter, _ = source_block_call_shape_fixture
    converter.__test_generated_getter_shape("SourceBlockCallShapeProbe.conflicted").should be_true
    converter.__test_generated_getter_shape("SourceBlockCallShapeOverload.generated").should be_true
  end

  it "finds the declaring accessor owner for an inherited generated getter" do
    converter, _ = source_block_call_shape_fixture
    converter.__test_generated_getter_shape("SourceBlockCallShapeChild.generated").should be_true
  end

  it "keeps a child source Def ahead of an inherited generated getter" do
    converter, _ = source_block_call_shape_fixture
    converter.__test_generated_getter_shape("SourceBlockCallShapeOverride.generated").should be_false
  end

  it "checks required and maximum positional arity from the exact Def" do
    converter, definitions = source_block_call_shape_fixture
    fixed = definitions["fixed"].first

    converter.__test_source_block_call_shape(fixed, 2).should be_true
    converter.__test_source_block_call_shape(fixed, 1).should be_false
    converter.__test_source_block_call_shape(fixed, 3).should be_false
  end

  it "admits omitted defaults without admitting missing or excess arguments" do
    converter, definitions = source_block_call_shape_fixture
    defaulted = definitions["defaulted"].first

    converter.__test_source_block_call_shape(defaulted, 1).should be_true
    converter.__test_source_block_call_shape(defaulted, 2).should be_true
    converter.__test_source_block_call_shape(defaulted, 0).should be_false
    converter.__test_source_block_call_shape(defaulted, 3).should be_false
  end

  it "checks named-only labels, required names, unknown names, and duplicate binding" do
    converter, definitions = source_block_call_shape_fixture
    named_only = definitions["named_only"].first
    pair = definitions["pair"].first

    converter.__test_source_block_call_shape(
      named_only, 1, named_names: ["first"], raw_positional_count: 0,
    ).should be_true
    converter.__test_source_block_call_shape(
      named_only, 2, named_names: ["first", "second"], raw_positional_count: 0,
    ).should be_true
    converter.__test_source_block_call_shape(
      named_only, 1, named_names: ["second"], raw_positional_count: 0,
    ).should be_false
    converter.__test_source_block_call_shape(
      named_only, 1, named_names: ["unknown"], raw_positional_count: 0,
    ).should be_false

    converter.__test_source_block_call_shape(
      pair, 2, named_names: ["first"], raw_positional_count: 1,
    ).should be_false
    converter.__test_source_block_call_shape(
      pair, 2, named_names: ["second"], raw_positional_count: 1,
    ).should be_true
  end

  it "uses the raw positional prefix instead of a default-filled normalized count" do
    converter, definitions = source_block_call_shape_fixture
    required_pair = definitions["required_pair"].first

    # The normalized shape has three slots, but only one positional source
    # argument plus `note:` was written. That cannot satisfy `second`.
    converter.__test_source_block_call_shape(
      required_pair, 3, has_block: true, named_names: ["note"], raw_positional_count: 1,
    ).should be_false

    # Two positional arguments and `note:` do satisfy the exact Def.
    converter.__test_source_block_call_shape(
      required_pair, 3, has_block: true, named_names: ["note"], raw_positional_count: 2,
    ).should be_true

    # Callers that already provide a normalized shape retain the legacy
    # contract when the raw source count is absent.
    converter.__test_source_block_call_shape(
      required_pair, 3, has_block: true, named_names: ["note"],
    ).should be_true
  end

  it "admits expanded tuple and packed NamedTuple splats with defaults and a block" do
    converter, definitions = source_block_call_shape_fixture
    tuple_splat = definitions["tuple_splat"].first
    keyword_splat = definitions["keyword_splat"].first
    required_pair = definitions["required_pair"].first

    # The tuple splat has already contributed one concrete positional slot;
    # the optional second parameter is supplied by its default.
    converter.__test_source_block_call_shape(
      tuple_splat, 1, has_block: true, has_splat: true,
    ).should be_true

    # The trailing NamedTuple represents the two keys produced by **. The
    # second named-only parameter is optional, so the one-key form is valid.
    converter.__test_source_block_call_shape(
      keyword_splat,
      1,
      has_block: true,
      named_names: ["first"],
      raw_positional_count: 0,
      has_splat: true,
      arg_type_names: ["NamedTuple(first: Int32)"],
    ).should be_true

    converter.__test_source_block_call_shape(
      keyword_splat,
      2,
      has_block: true,
      named_names: ["first", "second"],
      raw_positional_count: 0,
      has_splat: true,
      arg_type_names: ["NamedTuple(first: Int32, second: Int32)"],
    ).should be_true

    # A packed named key cannot replace a missing required positional slot.
    converter.__test_source_block_call_shape(
      required_pair,
      3,
      has_block: true,
      named_names: ["note"],
      raw_positional_count: 1,
      has_splat: true,
      arg_type_names: ["NamedTuple(note: Int32)"],
    ).should be_false
  end

  it "distinguishes explicit block parameters from a missing block" do
    converter, definitions = source_block_call_shape_fixture
    explicit_block = definitions["explicit_block"].first

    converter.__test_source_block_call_shape(explicit_block, 0, has_block: true).should be_true
    converter.__test_source_block_call_shape(explicit_block, 0, has_block: false).should be_false
  end

  it "admits an implicit yield block using the exact registered source arena" do
    converter, definitions = source_block_call_shape_fixture
    implicit_yield = definitions["implicit_yield"].first

    converter.__test_source_block_call_shape(implicit_yield, 1, has_block: true).should be_true
    converter.__test_source_block_call_shape(implicit_yield, 1, has_block: false).should be_false
  end

  it "does not let same-name overload caches replace the selected Def's shape" do
    converter, definitions = source_block_call_shape_fixture
    one_argument, two_arguments = definitions["overloaded"]

    converter.__test_poison_source_def_name_caches(one_argument, two_arguments)
    converter.__test_poison_source_def_name_caches(two_arguments, one_argument)

    converter.__test_source_block_call_shape(one_argument, 1).should be_true
    converter.__test_source_block_call_shape(one_argument, 2).should be_false
    converter.__test_source_block_call_shape(
      two_arguments, 2, named_names: ["option"], raw_positional_count: 1,
    ).should be_true
    converter.__test_source_block_call_shape(
      two_arguments, 1, named_names: ["option"], raw_positional_count: 0,
    ).should be_false
  end
end
