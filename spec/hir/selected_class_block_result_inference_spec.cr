require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  # Ask HIR about the caller's source tail directly. Each test creates a fresh
  # converter and only registers declarations; no function body is lowered, so
  # the selected helper has no lowered return cache to answer from.
  def __test_selected_class_block_result(
    owner_name : String,
    caller_method : String,
    expected_block : Bool? = true,
    trailing_block_arg : Bool = false,
  ) : String?
    caller_name = "#{owner_name}.#{caller_method}"
    matches = @function_defs.select do |name, _|
      name == caller_name || name.starts_with?("#{caller_name}$")
    end.values.uniq(&.object_id)
    raise "expected one registered caller #{caller_name}, got #{matches.size}" unless matches.size == 1

    caller_def = matches.first
    caller_arena = registered_arena_for_def(caller_def) ||
                   raise "caller #{caller_name} has no registered source arena"
    body = caller_def.body || raise "caller #{caller_name} has no body"
    call_expr = body.last? || raise "caller #{caller_name} has an empty body"

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
      call = node_for_expr(call_expr).as?(Adamas::Compiler::Frontend::CallNode) ||
             raise "caller #{caller_name} tail must be a CallNode"
      if expected_block != nil && expected_block != !call.block.nil?
        raise "caller #{caller_name} block presence did not match the requested probe"
      end
      if trailing_block_arg
        literal_block = call.block || raise "trailing-block probe requires a literal block"
        normalized = if named_args = call.named_args
                       Adamas::Compiler::Frontend::CallNode.new(call.span, call.callee, call.args + [literal_block], nil, named_args)
                     else
                       Adamas::Compiler::Frontend::CallNode.new(call.span, call.callee, call.args + [literal_block])
                     end
        call_expr = caller_arena.add(normalized)
      end

      @current_class = owner_name
      @current_method = caller_method
      @current_def_node = caller_def
      @current_method_is_class = true
      @infer_self_type_name = owner_name
      @infer_body_context = body
      @current_typeof_locals = {} of String => Adamas::HIR::TypeRef
      @current_typeof_local_names = {} of String => String

      infer_type_from_expr(call_expr, owner_name).try do |type_ref|
        get_type_name_from_ref(type_ref)
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

private def parse_selected_class_block_result_probe(source : String) : Adamas::HIR::AstToHir
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
  parsed.roots.each do |root_id|
    if node = parsed.arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end
  converter
end

private def selected_class_block_result_source : String
  <<-CRYSTAL
    class SelectedClassBlockGlobalOutput
    end

    class SelectedClassBlockNoBlockOutput
    end

    class SelectedClassBlockInstanceOutput
    end

    class SelectedClassBlockResultProbe
      class SelectedClassBlockGlobalOutput
      end

      def self.pair : Tuple(Int32, Int64)
        {65_i32, 66_i64}
      end

      def self.yield_once(&block : -> Tuple(Int32, Int64)) : Tuple(Int32, Int64)
        yield
      end

      def self.yield_twice(&block : -> Tuple(Int32, Int64)) : Tuple(Int32, Int64)
        yield_once { yield }
      end

      def self.one_layer_caller
        yield_once { pair }
      end

      def self.two_layer_caller
        yield_twice { pair }
      end

      def self.choice : SelectedClassBlockNoBlockOutput
        SelectedClassBlockNoBlockOutput.new
      end

      def self.choice(&block : -> Tuple(Int32, Int64)) : Tuple(Int32, Int64)
        yield
      end

      def self.no_block_overload_caller
        choice()
      end

      def self.block_overload_caller
        choice { pair }
      end

      def self.same_name(&block : -> Tuple(Int32, Int64)) : Tuple(Int32, Int64)
        yield
      end

      def same_name(&block : -> Tuple(Int32, Int64)) : SelectedClassBlockInstanceOutput
        SelectedClassBlockInstanceOutput.new
      end

      def self.same_name_instance_caller
        same_name { pair }
      end

      def self.needs_argument(value : Int32, &block : -> Tuple(Int32, Int64)) : Tuple(Int32, Int64)
        yield
      end

      def self.wrong_arity_caller
        needs_argument { pair }
      end

      def self.unannotated_yield(&block)
        yield
      end

      def self.unannotated_yield_caller
        unannotated_yield { pair }
      end

      def self.byte_result(value : UInt8, &block : -> Tuple(Int32, Int64)) : ::SelectedClassBlockGlobalOutput
        ::SelectedClassBlockGlobalOutput.new
      end

      def self.byte_positional_caller
        byte_result(65) { pair }
      end

      def self.byte_named_caller
        byte_result(value: 65) { pair }
      end

      def self.byte_out_of_range_caller
        byte_result(300) { pair }
      end

      def self.byte_named_out_of_range_caller
        byte_result(value: 300) { pair }
      end

      def self.qualified_output(&block : -> Tuple(Int32, Int64)) : ::SelectedClassBlockGlobalOutput
        ::SelectedClassBlockGlobalOutput.new
      end

      def self.qualified_context_caller : ::SelectedClassBlockGlobalOutput | SelectedClassBlockResultProbe::SelectedClassBlockGlobalOutput
        qualified_output { pair }
      end
    end
  CRYSTAL
end

describe "selected class block result inference with a fresh converter" do
  it "uses the exact selected class Def for one and two yielding helper layers" do
    converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
    converter.__test_selected_class_block_result(
      "SelectedClassBlockResultProbe", "one_layer_caller",
    ).should eq("Tuple(Int32, Int64)")

    converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
    converter.__test_selected_class_block_result(
      "SelectedClassBlockResultProbe", "two_layer_caller",
    ).should eq("Tuple(Int32, Int64)")
  end

  it "selects block and no-block overloads with their distinct declared results" do
    converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
    converter.__test_selected_class_block_result(
      "SelectedClassBlockResultProbe", "no_block_overload_caller", false,
    ).should eq("SelectedClassBlockNoBlockOutput")

    converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
    converter.__test_selected_class_block_result(
      "SelectedClassBlockResultProbe", "block_overload_caller",
    ).should eq("Tuple(Int32, Int64)")
  end

  it "does not answer a bare class helper from a same-name instance method" do
    converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
    converter.__test_selected_class_block_result(
      "SelectedClassBlockResultProbe", "same_name_instance_caller",
    ).should eq("Tuple(Int32, Int64)")
  end

  it "keeps a class call unresolved when its selected overload has wrong arity" do
    converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
    converter.__test_selected_class_block_result(
      "SelectedClassBlockResultProbe", "wrong_arity_caller",
    ).should be_nil
  end

  it "does not invent a block-dependent result without a declared contract" do
    converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
    converter.__test_selected_class_block_result(
      "SelectedClassBlockResultProbe", "unannotated_yield_caller",
    ).should be_nil
  end

  it "does not count a normalized trailing literal block as a positional argument" do
    converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
    converter.__test_selected_class_block_result(
      "SelectedClassBlockResultProbe", "block_overload_caller", trailing_block_arg: true,
    ).should eq("Tuple(Int32, Int64)")
  end

  it "keeps caller output context and a nested shadow from replacing a qualified helper result" do
    converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
    converter.__test_selected_class_block_result(
      "SelectedClassBlockResultProbe", "qualified_context_caller",
    ).should eq("SelectedClassBlockGlobalOutput")
  end

  it "reselects literal-block overloads after admitted positional and named integer conversion" do
    ["byte_positional_caller", "byte_named_caller"].each do |caller|
      converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
      converter.__test_selected_class_block_result(
        "SelectedClassBlockResultProbe", caller,
      ).should eq("SelectedClassBlockGlobalOutput")
    end
  end

  it "does not admit an out-of-range positional or named literal for a block overload" do
    ["byte_out_of_range_caller", "byte_named_out_of_range_caller"].each do |caller|
      converter = parse_selected_class_block_result_probe(selected_class_block_result_source)
      converter.__test_selected_class_block_result(
        "SelectedClassBlockResultProbe", caller,
      ).should be_nil
    end
  end
end
