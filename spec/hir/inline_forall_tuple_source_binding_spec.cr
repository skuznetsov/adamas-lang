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

  def __test_forwarded_callback_input_kind(class_object : Bool, mixed : Bool) : Bool
    facts = mixed ? [{TypeRef::INT32, false}, {TypeRef::INT32, true}] : nil
    exact_inline_callback_input?(SourceCallArgument.new(TypeRef::INT32, class_object, value_facts: facts))
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
      probe_function = @module.create_function("__inline_tuple_source_probe", TypeRef::VOID)
      probe_context = Adamas::HIR::LoweringContext.new(probe_function, @module, block_arena)
      witness = inline_block_return_source_witness(
        probe_context,
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
          witness.result,
          {} of String => String,
        )
      end
    ensure
      @current_class = old_class
      @current_namespace_override = old_namespace
    end
  end

  def __test_source_return_result_target(
    prefix : String,
  ) : Tuple(String, Adamas::HIR::Function, Bool)
    name = @function_defs.keys.sort.find do |candidate|
      next false unless candidate.starts_with?(prefix)
      function = @module.function_by_name(candidate)
      !!function.try(&.source_return_result_receipt)
    end || raise "expected source-result receipt for #{prefix}"
    function = @module.function_by_name(name) || raise "missing HIR function #{name}"
    definition = @function_defs[name]? || raise "missing source Def for #{name}"
    declaration_arena = @function_def_arenas[name]? || raise "missing source arena for #{name}"
    facts = fresh_source_return_result_facts(name, function, definition, declaration_arena)
    {name, function, !facts.nil?}
  end

  def __test_fresh_source_return_result_facts(
    name : String,
  ) : Array({Adamas::HIR::TypeRef, Bool})?
    function = @module.function_by_name(name) || return nil
    definition = @function_defs[name]? || return nil
    declaration_arena = @function_def_arenas[name]? || return nil
    fresh_source_return_result_facts(name, function, definition, declaration_arena)
  end

  def __test_generated_allocator_call_witness(
    prefix : String,
  ) : Tuple(String, Adamas::HIR::Function, Adamas::HIR::Call, String, String)?
    name = nil.as(String?)
    source_call = nil.as(Adamas::HIR::Call?)
    target_name = nil.as(String?)
    @function_defs.keys.sort.each do |candidate|
      next unless candidate.starts_with?(prefix)
      source_function = @module.function_by_name(candidate) || next
      source_function.blocks.each do |block|
        block.instructions.each do |instruction|
          call = instruction.as?(Adamas::HIR::Call) || next
          selected_target = @generated_allocator_calls[{source_function, call.id}]? || next
          name = candidate
          source_call = call
          target_name = selected_target
          break
        end
        break if source_call
      end
      break if source_call
    end
    source_name = name || return nil
    source_function = @module.function_by_name(source_name) || return nil
    call = source_call || return nil
    allocator_name = target_name || return nil
    layout = @generated_allocator_layout_bodies[allocator_name]? || return nil
    return nil unless materialized_generated_allocator(allocator_name)
    begin
      validate_generated_allocator_call_contract!(source_function, call, allocator_name)
    rescue ex : Adamas::HIR::LoweringError
      return nil
    end
    {source_name, source_function, call, allocator_name, layout[2]}
  end

  def __test_fresh_generated_allocator_source_facts(
    source_name : String,
  ) : Array({Adamas::HIR::TypeRef, Bool})?
    __test_fresh_source_return_result_facts(source_name)
  end

  def __test_generated_allocator_class_type(class_name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(class_name)
  end

  def __test_generated_allocator_is_materialized?(target_name : String) : Bool
    !materialized_generated_allocator(target_name).nil?
  end

  def __test_mutate_generated_allocator_body(target_name : String) : UInt64
    allocator = @module.function_by_name(target_name) || raise "generated allocator body was not found"
    revision = allocator.body_revision
    block = allocator.blocks.first? || raise "generated allocator has no entry block"
    block.insert(
      0,
      Adamas::HIR::Literal.new(
        allocator.next_value_id,
        Adamas::HIR::TypeRef::BOOL,
        true,
      ),
    )
    revision
  end

  def __test_invalidate_generated_allocator_layout(target_name : String) : Nil
    layout = @generated_allocator_layout_bodies[target_name]? || raise "generated allocator layout proof was not found"
    invalidate_generated_allocator_state(layout[2], layout[2], true)
  end
end

private def inline_forall_tuple_source_harness(
  expression : String,
  output : String = "Tuple(K, V)",
  input : String = "Int32",
  lexical_bindings : Hash(String, String) = {} of String => String,
  extra_item_methods : String = "",
) : Tuple(Adamas::HIR::AstToHir, Hash(String, String)?)
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
    class InlineForallTupleSourceItem
      def piece
        42
      end
      def kind
        InlineForallTupleSourcePayload
      end
      def broad : Int
        42
      end
      def bottom : Bool
        loop do
        end
      end
    #{extra_item_methods}
    end
    class InlineForallTupleSourceConstructed
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
  bindings = converter.__test_inline_forall_tuple_source_bindings(
    block || raise("expected callback block"), arena, lexical_bindings,
  )
  {converter, bindings}
end

private def inline_forall_tuple_source_bindings(
  expression : String,
  output : String = "Tuple(K, V)",
  input : String = "Int32",
  lexical_bindings : Hash(String, String) = {} of String => String,
) : Hash(String, String)?
  inline_forall_tuple_source_harness(expression, output, input, lexical_bindings)[1]
end

private def replace_first_integer_literal(
  function : Adamas::HIR::Function,
  tracked : Bool,
) : Tuple(Adamas::HIR::Block, Int32)
  block = function.blocks.find do |candidate|
    candidate.instructions.any?(&.is_a?(Adamas::HIR::Literal))
  end || raise "expected an integer literal in #{function.name}"
  index = block.instructions.index(&.is_a?(Adamas::HIR::Literal)) || raise "missing integer literal"
  previous = block.instructions[index].as(Adamas::HIR::Literal)
  replacement = Adamas::HIR::Literal.new(previous.id, previous.type, previous.int_value + 1_i64)
  if tracked
    block.replace(index, replacement)
  else
    # Exercise the public mutable Array path that bypasses FunctionRevisionLedger.
    block.instructions[index] = replacement
  end
  {block, index}
end

describe "inline forall tuple source prebinding" do
  it "requires a single source kind even when mixed inputs share one carrier" do
    converter, _ = inline_forall_tuple_source_harness("{item, item}")
    converter.__test_forwarded_callback_input_kind(false, false).should be_true
    converter.__test_forwarded_callback_input_kind(true, false).should be_true
    converter.__test_forwarded_callback_input_kind(false, true).should be_false
  end

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

  it "binds member Tuple leaves from exact completed bodies" do
    inline_forall_tuple_source_bindings(
      "{item.piece, item}", input: "InlineForallTupleSourceItem",
    ).should eq({"K" => "Int32", "V" => "InlineForallTupleSourceItem"})
    inline_forall_tuple_source_bindings(
      "{item.kind, true}", input: "InlineForallTupleSourceItem",
    ).should eq({"K" => "InlineForallTupleSourcePayload.class", "V" => "Bool"})
    inline_forall_tuple_source_bindings(
      "{item.broad, true}", input: "InlineForallTupleSourceItem",
    ).should eq({"K" => "Int32", "V" => "Bool"})
  end

  it "retains the exact generated allocator receipt for a bare static new result" do
    converter, bindings = inline_forall_tuple_source_harness(
      "{item.constructed_piece, item}",
      input: "InlineForallTupleSourceItem",
      extra_item_methods: "      def constructed_piece\n        InlineForallTupleSourceConstructed.new\n      end\n",
    )
    bindings.should eq({
      "K" => "InlineForallTupleSourceConstructed",
      "V" => "InlineForallTupleSourceItem",
    })

    witness = converter.__test_generated_allocator_call_witness(
      "InlineForallTupleSourceItem#constructed_piece",
    ) || raise "bare static new did not retain its generated allocator call witness"
    source_name, _, call, allocator_name, allocator_class = witness
    allocator_class.should eq("InlineForallTupleSourceConstructed")
    call.method_name.should eq(allocator_name)
    call.type.should eq(converter.__test_generated_allocator_class_type(allocator_class))
    converter.__test_fresh_generated_allocator_source_facts(source_name).should eq([{call.type, false}])
  end

  it "rejects the source result after the generated allocator body changes" do
    converter, bindings = inline_forall_tuple_source_harness(
      "{item.constructed_piece, item}",
      input: "InlineForallTupleSourceItem",
      extra_item_methods: "      def constructed_piece\n        InlineForallTupleSourceConstructed.new\n      end\n",
    )
    bindings.should eq({
      "K" => "InlineForallTupleSourceConstructed",
      "V" => "InlineForallTupleSourceItem",
    })
    source_name, _, _, allocator_name, _ = converter.__test_generated_allocator_call_witness(
      "InlineForallTupleSourceItem#constructed_piece",
    ).not_nil!
    converter.__test_fresh_generated_allocator_source_facts(source_name).should_not be_nil
    converter.__test_generated_allocator_is_materialized?(allocator_name).should be_true

    original_revision = converter.__test_mutate_generated_allocator_body(allocator_name)
    allocator = converter.module.function_by_name(allocator_name).not_nil!
    allocator.body_revision.should be > original_revision
    converter.__test_generated_allocator_is_materialized?(allocator_name).should be_false
    converter.__test_fresh_generated_allocator_source_facts(source_name).should be_nil
  end

  it "rejects the source result after its generated layout proof is invalidated" do
    converter, bindings = inline_forall_tuple_source_harness(
      "{item.constructed_piece, item}",
      input: "InlineForallTupleSourceItem",
      extra_item_methods: "      def constructed_piece\n        InlineForallTupleSourceConstructed.new\n      end\n",
    )
    bindings.should eq({
      "K" => "InlineForallTupleSourceConstructed",
      "V" => "InlineForallTupleSourceItem",
    })
    source_name, _, _, allocator_name, _ = converter.__test_generated_allocator_call_witness(
      "InlineForallTupleSourceItem#constructed_piece",
    ).not_nil!
    converter.__test_fresh_generated_allocator_source_facts(source_name).should_not be_nil

    converter.__test_invalidate_generated_allocator_layout(allocator_name)
    converter.__test_generated_allocator_is_materialized?(allocator_name).should be_false
    converter.__test_fresh_generated_allocator_source_facts(source_name).should be_nil
  end

  it "does not bind a bottom member result from its Bool annotation" do
    inline_forall_tuple_source_bindings(
      "{item.bottom, true}", input: "InlineForallTupleSourceItem",
    ).should be_nil
  end

  it "rejects a source-result receipt after a tracked body replacement" do
    converter, bindings = inline_forall_tuple_source_harness(
      "{item.piece, item}", input: "InlineForallTupleSourceItem",
    )
    bindings.should eq({"K" => "Int32", "V" => "InlineForallTupleSourceItem"})
    name, function, admitted = converter.__test_source_return_result_target(
      "InlineForallTupleSourceItem#piece",
    )
    admitted.should be_true
    original_revision = function.body_revision
    replace_first_integer_literal(function, tracked: true)
    function.body_revision.should be > original_revision
    converter.__test_fresh_source_return_result_facts(name).should be_nil
  end

  it "rejects a source-result receipt after an untracked instruction-array edit" do
    converter, bindings = inline_forall_tuple_source_harness(
      "{item.piece, item}", input: "InlineForallTupleSourceItem",
    )
    bindings.should eq({"K" => "Int32", "V" => "InlineForallTupleSourceItem"})
    name, function, admitted = converter.__test_source_return_result_target(
      "InlineForallTupleSourceItem#piece",
    )
    admitted.should be_true
    original_revision = function.body_revision
    replace_first_integer_literal(function, tracked: false)
    function.body_revision.should eq(original_revision)
    converter.__test_fresh_source_return_result_facts(name).should be_nil
  end

  it "rejects an untracked replacement with identical debug text" do
    converter, bindings = inline_forall_tuple_source_harness(
      "{item.piece, item}", input: "InlineForallTupleSourceItem",
    )
    bindings.should eq({"K" => "Int32", "V" => "InlineForallTupleSourceItem"})
    name, function, admitted = converter.__test_source_return_result_target(
      "InlineForallTupleSourceItem#piece",
    )
    admitted.should be_true
    block = function.blocks.find do |candidate|
      candidate.instructions.any?(&.is_a?(Adamas::HIR::Literal))
    end || raise "expected an integer literal in #{function.name}"
    index = block.instructions.index(&.is_a?(Adamas::HIR::Literal)) || raise "missing integer literal"
    previous = block.instructions[index].as(Adamas::HIR::Literal)
    replacement = Adamas::HIR::Literal.new(previous.id, previous.type, previous.int_value)
    previous_text = String.build { |io| previous.to_s(io) }
    replacement_text = String.build { |io| replacement.to_s(io) }
    replacement_text.should eq(previous_text)

    original_revision = function.body_revision
    block.instructions[index] = replacement
    function.body_revision.should eq(original_revision)
    converter.__test_fresh_source_return_result_facts(name).should be_nil
  end

  it "recursively invalidates a caller receipt when a direct callee body changes" do
    converter, bindings = inline_forall_tuple_source_harness(
      "{item.wrapper_piece, item}",
      input: "InlineForallTupleSourceItem",
      extra_item_methods: "      def wrapper_piece\n        piece\n      end\n",
    )
    bindings.should eq({"K" => "Int32", "V" => "InlineForallTupleSourceItem"})
    wrapper_name, wrapper, wrapper_admitted = converter.__test_source_return_result_target(
      "InlineForallTupleSourceItem#wrapper_piece",
    )
    wrapper_admitted.should be_true
    call = wrapper.blocks.flat_map(&.instructions).find(&.is_a?(Adamas::HIR::Call))
      .try(&.as(Adamas::HIR::Call)) || raise "expected a direct HIR call in wrapper_piece"
    call.virtual.should be_false
    call.has_block?.should be_false
    callee_name, callee, callee_admitted = converter.__test_source_return_result_target(
      call.method_name,
    )
    callee_admitted.should be_true
    callee_name.should start_with("InlineForallTupleSourceItem#piece")
    replace_first_integer_literal(callee, tracked: false)
    converter.__test_fresh_source_return_result_facts(wrapper_name).should be_nil
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
