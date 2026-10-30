require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  # Infer each direct call in one caller body with the same converter. This
  # exercises selected source return inference before any body is lowered or
  # a representative family return cache is populated.
  def __test_selected_block_call_local_results(
    owner_name : String,
    caller_method : String,
  ) : Array(String?)
    caller_name = "#{owner_name}.#{caller_method}"
    matches = @function_defs.select do |name, _|
      name == caller_name || name.starts_with?("#{caller_name}$")
    end.values.uniq(&.object_id)
    raise "expected one registered caller #{caller_name}, got #{matches.size}" unless matches.size == 1

    caller_def = matches.first
    caller_arena = registered_arena_for_def(caller_def) ||
                   raise "caller #{caller_name} has no registered source arena"
    body = caller_def.body || raise "caller #{caller_name} has no body"

    old_arena = @arena
    old_current_class = @current_class
    old_current_method = @current_method
    old_current_def = @current_def_node
    old_current_method_is_class = @current_method_is_class
    old_infer_self_type_name = @infer_self_type_name
    old_infer_body_context = @infer_body_context
    old_typeof_locals = @current_typeof_locals
    old_typeof_names = @current_typeof_local_names

    begin
      @arena = caller_arena
      @current_class = owner_name
      @current_method = caller_method
      @current_def_node = caller_def
      @current_method_is_class = true
      @infer_self_type_name = owner_name
      @infer_body_context = body
      @current_typeof_locals = {} of String => Adamas::HIR::TypeRef
      @current_typeof_local_names = {} of String => String

      body.map do |expr_id|
        unless node_for_expr(expr_id).is_a?(Adamas::Compiler::Frontend::CallNode)
          raise "caller #{caller_name} body must contain direct CallNodes"
        end
        infer_type_from_expr(expr_id, owner_name).try do |type_ref|
          get_type_name_from_ref(type_ref)
        end
      end
    ensure
      @arena = old_arena
      @current_class = old_current_class
      @current_method = old_current_method
      @current_def_node = old_current_def
      @current_method_is_class = old_current_method_is_class
      @infer_self_type_name = old_infer_self_type_name
      @infer_body_context = old_infer_body_context
      @current_typeof_locals = old_typeof_locals
      @current_typeof_local_names = old_typeof_names
    end
  end

  # Return source-level type-literal evidence for each block tail independently
  # of its TypeRef. TypeRef names erase the metaclass marker, so this keeps the
  # kind assertion tied to the original callback expression.
  def __test_selected_block_call_local_literal_results(
    owner_name : String,
    caller_method : String,
  ) : Array(String?)
    caller_name = "#{owner_name}.#{caller_method}"
    matches = @function_defs.select do |name, _|
      name == caller_name || name.starts_with?("#{caller_name}$")
    end.values.uniq(&.object_id)
    raise "expected one registered caller #{caller_name}, got #{matches.size}" unless matches.size == 1

    caller_def = matches.first
    caller_arena = registered_arena_for_def(caller_def) ||
                   raise "caller #{caller_name} has no registered source arena"
    body = caller_def.body || raise "caller #{caller_name} has no body"

    old_arena = @arena
    old_current_class = @current_class
    old_current_method = @current_method
    begin
      @arena = caller_arena
      @current_class = owner_name
      @current_method = caller_method

      body.map do |expr_id|
        call = node_for_expr(expr_id).as?(Adamas::Compiler::Frontend::CallNode) ||
               raise "caller #{caller_name} body must contain direct CallNodes"
        block_id = call.block || raise "call in #{caller_name} must have a literal block"
        block = node_for_expr(block_id).as?(Adamas::Compiler::Frontend::BlockNode) ||
                raise "call block in #{caller_name} must be a BlockNode"
        tail_id = tail_expr_id_for_body(block.body) ||
                  raise "call block in #{caller_name} must have a source tail"
        infer_type_literal_name_from_expr(tail_id)
      end
    ensure
      @arena = old_arena
      @current_class = old_current_class
      @current_method = old_current_method
    end
  end

  # Ask the production inline-block return inference path for each literal
  # callback in one registered caller. Keep the caller Def and its registered
  # arena active so path and local resolution match ordinary source inference.
  def __test_selected_block_inline_return_names(
    owner_name : String,
    caller_method : String,
  ) : Array(String?)
    caller_name = "#{owner_name}.#{caller_method}"
    matches = @function_defs.select do |name, _|
      name == caller_name || name.starts_with?("#{caller_name}$")
    end.values.uniq(&.object_id)
    raise "expected one registered caller #{caller_name}, got #{matches.size}" unless matches.size == 1

    caller_def = matches.first
    caller_arena = registered_arena_for_def(caller_def) ||
                   raise "caller #{caller_name} has no registered source arena"
    body = caller_def.body || raise "caller #{caller_name} has no body"

    old_arena = @arena
    old_current_class = @current_class
    old_current_method = @current_method
    old_current_def = @current_def_node
    old_current_method_is_class = @current_method_is_class
    old_infer_self_type_name = @infer_self_type_name
    old_infer_body_context = @infer_body_context
    old_typeof_locals = @current_typeof_locals
    old_typeof_names = @current_typeof_local_names

    begin
      @arena = caller_arena
      @current_class = owner_name
      @current_method = caller_method
      @current_def_node = caller_def
      @current_method_is_class = true
      @infer_self_type_name = owner_name
      @infer_body_context = body
      @current_typeof_locals = {} of String => Adamas::HIR::TypeRef
      @current_typeof_local_names = {} of String => String

      body.map do |expr_id|
        call = node_for_expr(expr_id).as?(Adamas::Compiler::Frontend::CallNode) ||
               raise "caller #{caller_name} body must contain direct CallNodes"
        block_id = call.block || raise "call in #{caller_name} must have a literal block"
        block = node_for_expr(block_id).as?(Adamas::Compiler::Frontend::BlockNode) ||
                raise "call block in #{caller_name} must be a BlockNode"
        inline_block_return_type_name(block, nil, owner_name)
      end
    ensure
      @arena = old_arena
      @current_class = old_current_class
      @current_method = old_current_method
      @current_def_node = old_current_def
      @current_method_is_class = old_current_method_is_class
      @infer_self_type_name = old_infer_self_type_name
      @infer_body_context = old_infer_body_context
      @current_typeof_locals = old_typeof_locals
      @current_typeof_local_names = old_typeof_names
    end
  end
end

private def selected_block_call_local_result_fixture : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class SelectedBlockCallLocalMarker
    end

    alias SelectedBlockCallLocalDiscardResult = Nil

    class SelectedBlockCallLocalResultProbe
      def self.output(&block : -> T) : T forall T
        yield.as(T)
      end

      def self.nullable_output(&block : -> T?) : T? forall T
        yield
      end

      def self.nullable_early_return(flag : Bool, &block : -> T?) : Int32 | T? forall T
        unless flag
          return 1
        end
        yield
      end

      def self.array_item(&block : -> Array(T)) : T forall T
        yield.first
      end

      def self.with_nullable_input(value : T? = nil, &block : -> T) : T forall T
        yield.as(T)
      end

      def self.yield_nil(&block : -> Nil)
        yield
      end

      def self.yield_alias(&block : -> Nil) : SelectedBlockCallLocalDiscardResult
        yield
      end

      # The first assignment comes from yield, but a nested branch can replace
      # it before the method returns. Selected-call inference must not treat the
      # callback value as the sole method result on that evidence alone.
      def self.nested_overwrite(flag : Bool, &block : -> Nil)
        value = yield
        if flag
          value = "fixed"
        end
        value
      end

      # This wraps the yielded value instead of returning it directly. Without
      # an explicit source result contract, selected-call inference must not
      # guess the wrapper's type from the callback alone.
      def self.unannotated_wrapped(&block : -> T) forall T
        {yield}
      end

      def self.repeated_output_results
        output { 65_i32 }
        output { nil }
        output { SelectedBlockCallLocalMarker }
      end

      def self.inline_block_return_name_results
        output { SelectedBlockCallLocalMarker }
        output do
          selected_marker = SelectedBlockCallLocalMarker
          selected_marker
        end
        output { 76_i32 }
        output { nil }
        nullable_output { SelectedBlockCallLocalMarker }
        nullable_output { nil }
      end

      def self.nullable_output_results
        nullable_output { 66_i64 }
        nullable_output { nil }
      end

      def self.nullable_early_return_result
        nullable_early_return(true) { 66_i64 }
      end

      def self.array_item_results
        array_item { [] of Int32 }
        array_item { [] of String }
      end

      def self.default_and_explicit_input_results
        with_nullable_input { 67_i32 }
        with_nullable_input(68_i64) { 68_i64 }
        with_nullable_input(69_i64) { 70_i32 }
      end

      def self.nil_contract_yield_result
        yield_nil { 71_i32 }
      end

      def self.alias_nil_contract_yield_result
        yield_alias { 72_i32 }
      end

      def self.nested_overwrite_result
        nested_overwrite(true) { 74_i32 }
      end

      def self.unannotated_wrapped_result
        unannotated_wrapped { 73_i32 }
      end
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
  # The CLI seeds root type names before source registration. An unseeded
  # top-level alias would exercise an invalid declaration context instead of
  # cold selected-call inference.
  converter.seed_top_level_type_names([
    "SelectedBlockCallLocalMarker",
    "SelectedBlockCallLocalDiscardResult",
    "SelectedBlockCallLocalResultProbe",
  ])
  parsed.roots.each do |root_id|
    case node = parsed.arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::AliasNode
      converter.register_alias(node)
    end
  end
  converter
end

describe "selected class block call results in one cold caller body" do
  it "preserves class-literal kind through inline callback return inference" do
    converter = selected_block_call_local_result_fixture
    converter.__test_selected_block_inline_return_names(
      "SelectedBlockCallLocalResultProbe", "inline_block_return_name_results",
    ).should eq([
      "SelectedBlockCallLocalMarker.class",
      "SelectedBlockCallLocalMarker.class",
      "Int32",
      "Nil",
      "SelectedBlockCallLocalMarker.class",
      "Nil",
    ])
  end

  it "does not reuse a previous call's generic result, including a type-literal source" do
    converter = selected_block_call_local_result_fixture
    converter.__test_selected_block_call_local_results(
      "SelectedBlockCallLocalResultProbe", "repeated_output_results",
    ).should eq([
      "Int32",
      "Nil",
      "SelectedBlockCallLocalMarker",
    ])

    converter = selected_block_call_local_result_fixture
    converter.__test_selected_block_call_local_literal_results(
      "SelectedBlockCallLocalResultProbe", "repeated_output_results",
    ).should eq([nil, nil, "SelectedBlockCallLocalMarker"])
  end

  it "binds nullable and nested generic callback outputs per call" do
    converter = selected_block_call_local_result_fixture
    converter.__test_selected_block_call_local_results(
      "SelectedBlockCallLocalResultProbe", "nullable_output_results",
    ).should eq(["Int64", "Nil"])

    converter = selected_block_call_local_result_fixture
    converter.__test_selected_block_call_local_results(
      "SelectedBlockCallLocalResultProbe", "array_item_results",
    ).should eq(["Int32", "String"])
  end

  it "keeps omitted nullable input distinct from a supplied input binding" do
    converter = selected_block_call_local_result_fixture
    converter.__test_selected_block_call_local_results(
      "SelectedBlockCallLocalResultProbe", "default_and_explicit_input_results",
    ).should eq(["Int32", "Int64", nil])
  end

  it "does not narrow an annotated result to yield across an early return" do
    converter = selected_block_call_local_result_fixture
    result = converter.__test_selected_block_call_local_results(
      "SelectedBlockCallLocalResultProbe", "nullable_early_return_result",
    ).first
    result.should_not eq("Int64")
  end

  it "uses the yielded expression result when the block adapter discards its result" do
    converter = selected_block_call_local_result_fixture
    converter.__test_selected_block_call_local_results(
      "SelectedBlockCallLocalResultProbe", "nil_contract_yield_result",
    ).should eq(["Int32"])

    converter = selected_block_call_local_result_fixture
    converter.__test_selected_block_call_local_results(
      "SelectedBlockCallLocalResultProbe", "alias_nil_contract_yield_result",
    ).should eq(["Nil"])
  end

  it "does not treat a yielded assignment as passthrough when a nested branch overwrites the tail local" do
    converter = selected_block_call_local_result_fixture
    result = converter.__test_selected_block_call_local_results(
      "SelectedBlockCallLocalResultProbe", "nested_overwrite_result",
    ).first

    # Full body inference is outside this cold-call helper, so nil is acceptable;
    # the callback's Int32 alone is not a sound result for this method.
    result.should_not eq("Int32")
  end

  it "leaves a non-passthrough unannotated block result unresolved" do
    converter = selected_block_call_local_result_fixture
    converter.__test_selected_block_call_local_results(
      "SelectedBlockCallLocalResultProbe", "unannotated_wrapped_result",
    ).should eq([nil])
  end
end
