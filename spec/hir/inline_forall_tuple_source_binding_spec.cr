require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_register_top_level_source_def(
    definition : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    name = safe_slice_to_string(definition.name) || raise "top-level Def has no name"
    register_function_def(name, definition, arena)
  end

  def __test_inline_tuple_source_descriptor_guard(shape_mismatch : Bool) : Tuple(Bool, Bool)
    pattern = build_source_block_result_pattern(
      "Tuple(K, V)", nil, ["K", "V"], {} of String => String,
    )
    actual = canonical_bound_type_ref("Tuple(Int32, Bool)")
    values = [SourceCallArgument.new(TypeRef::INT32, true)]
    unless shape_mismatch
      # The second witness claims an Int32 slot, but the ABI slot is Bool.
      values << SourceCallArgument.new(TypeRef::INT32, false)
    end
    inferred = {} of String => SourceCallArgument
    matched = source_block_result_pattern_match_into?(
      actual, pattern, inferred, actual_tuple_values: values,
    )
    {matched, inferred.empty?}
  end

  def __test_inline_forall_tuple_source_bindings(
    block : Adamas::Compiler::Frontend::BlockNode,
    block_arena : Adamas::Compiler::Frontend::ArenaLike,
    lexical_bindings : Hash(String, String) = {} of String => String,
  ) : Hash(String, String)?
    owner = "InlineForallTupleSourceProbe"
    selected_name = "#{owner}.transform"
    definitions = @function_defs.select do |name, _|
      name == selected_name || name.starts_with?("#{selected_name}$")
    end.values.uniq(&.object_id)
    raise "expected one source transform Def, got #{definitions.size}" unless definitions.size == 1
    definition = definitions.first
    declaration_arena = registered_arena_for_def(definition) ||
                        raise "transform Def has no declaration arena"

    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = owner
    @current_namespace_override = owner
    begin
      value = inline_block_return_source_argument(
        block,
        block_arena,
        definition,
        declaration_arena,
        owner,
        {} of String => String,
        BlockOwner.new(nil, nil, false, method_source_yield_context(definition, declaration_arena)),
        lexical_bindings,
      ) || return nil
      with_arena(declaration_arena) do
        source_block_output_type_bindings(
          definition,
          owner,
          value,
          {} of String => String,
        )
      end
    ensure
      @current_class = old_class
      @current_namespace_override = old_namespace
    end
  end
end

private def inline_forall_tuple_source_bindings(
  expression : String,
  output : String = "Tuple(K, V)",
  input : String = "Int32",
  lexical_bindings : Hash(String, String) = {} of String => String,
) : Hash(String, String)?
  source = <<-CRYSTAL
    def truth : Bool
      true
    end

    def broad_integer : Int
      1
    end

    def broad_value : Value
      1
    end

    def broad_class : Class
      Int32
    end

    class InlineForallTupleSourcePayload
    end
    class InlineForallTupleSourceProbe
      class InlineForallTupleSourcePayload
      end
      def self.transform(&block : #{input} -> #{output}) : Tuple(K, V) forall K, V
        yield 1
      end
    end

    InlineForallTupleSourceProbe.transform { |item| #{expression} }
    CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  parsed = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?
  arena = parsed.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.arena = arena

  block = nil.as(Adamas::Compiler::Frontend::BlockNode?)
  parsed.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.__test_register_top_level_source_def(node, arena)
    when Adamas::Compiler::Frontend::CallNode
      if block_id = node.block
        block = arena[block_id].as?(Adamas::Compiler::Frontend::BlockNode)
      end
    end
  end
  converter.__test_inline_forall_tuple_source_bindings(block || raise("expected callback block"), arena, lexical_bindings)
end

describe "inline forall tuple source prebinding" do
  it "binds ordinary tuple slots from callback inputs and literals" do
    inline_forall_tuple_source_bindings("{item, true}").should eq({"K" => "Int32", "V" => "Bool"})
  end

  it "preserves class-valued tuple slots" do
    inline_forall_tuple_source_bindings("{Int32, true}").should eq({"K" => "Int32.class", "V" => "Bool"})
    inline_forall_tuple_source_bindings("{item, Bool}").should eq({"K" => "Int32", "V" => "Bool.class"})
  end

  it "retains slot source kinds through a nullable tuple output restriction" do
    inline_forall_tuple_source_bindings("{Int32, true}", "Tuple(K, V) | Nil").should eq({
      "K" => "Int32.class", "V" => "Bool",
    })
  end

  it "preserves nested tuple and local-alias source kinds" do
    inline_forall_tuple_source_bindings("{ {Int32, item}, true }").should eq({
      "K" => "Tuple(Int32.class, Int32)",
      "V" => "Bool",
    })
    inline_forall_tuple_source_bindings("kind = Int32; {kind, true}").should eq({
      "K" => "Int32.class",
      "V" => "Bool",
    })
  end

  it "resolves callback type paths and formals in their lexical source owner" do
    inline_forall_tuple_source_bindings("{InlineForallTupleSourcePayload, true}").should eq({
      "K" => "InlineForallTupleSourcePayload.class", "V" => "Bool",
    })
    inline_forall_tuple_source_bindings(
      "{T, true}", lexical_bindings: {"T" => "Bool", "K" => "Int64"},
    ).should eq({"K" => "Bool.class", "V" => "Bool"})
  end

  it "declines callback inputs whose source domain needs more than an ABI witness" do
    inline_forall_tuple_source_bindings("{item, true}", input: "Int32 | Bool").should be_nil
    inline_forall_tuple_source_bindings(
      "{item, true}", input: "Tuple(Int32.class, Bool) | Tuple(Int32, Bool)",
    ).should be_nil
    inline_forall_tuple_source_bindings("{item, true}", input: "Int").should be_nil
  end

  it "rejects a structured witness paired with another tuple descriptor" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(""))
    converter = Adamas::HIR::AstToHir.new(parser.parse_program.arena)
    converter.__test_inline_tuple_source_descriptor_guard(false).should eq({false, true})
    converter.__test_inline_tuple_source_descriptor_guard(true).should eq({false, true})
  end

  it "declines call leaves whose annotations do not prove their actual result" do
    inline_forall_tuple_source_bindings("{item, truth}").should be_nil
    inline_forall_tuple_source_bindings("return {item, true}").should be_nil
  end

  it "declines unknown, joined, and broad-annotation leaves" do
    inline_forall_tuple_source_bindings("{item, missing_source_value}").should be_nil
    inline_forall_tuple_source_bindings("{item, if true; true; else; false; end}").should be_nil
    inline_forall_tuple_source_bindings("{item, broad_integer}").should be_nil
    inline_forall_tuple_source_bindings("{item, broad_value}").should be_nil
    inline_forall_tuple_source_bindings("{item, broad_class}").should be_nil
  end

  it "invalidates local witnesses after unsupported prefix control flow or writes" do
    inline_forall_tuple_source_bindings(
      "kind = Int32; if true; kind = 1; end; {kind, true}",
    ).should be_nil
    inline_forall_tuple_source_bindings("kind = Int32; kind += 1; {kind, true}").should be_nil
    inline_forall_tuple_source_bindings("kind = Int32; first, kind = 1, 2; {kind, true}").should be_nil
    inline_forall_tuple_source_bindings("kind = Int32; -> { kind = 1 }; {kind, true}").should be_nil
  end
end
