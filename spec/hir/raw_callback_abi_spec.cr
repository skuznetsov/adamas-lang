require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def raw_callback_parse(code : String) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

# This test-only subclass supplies a stale early block return fact. The actual
# block body still lowers normally, so a mismatch exercises the late alias path
# without adding a production hook or changing the source AST.
private class StaleRawCallbackReturnAstToHir < Adamas::HIR::AstToHir
  @stale_forward_return_calls : Int32 = 0

  private def block_return_type_name(
    _ctx : Adamas::HIR::LoweringContext,
    _block_id : Adamas::HIR::BlockId,
  ) : String?
    "Int32"
  end

  private def get_function_return_type(
    name : String,
    call_arg_count : Int32? = nil,
    selected_def : Adamas::Compiler::Frontend::DefNode? = nil,
  ) : Adamas::HIR::TypeRef
    if ENV["ADAMAS_TEST_STALE_FORWARD_RETURN"]? == "1" &&
       name.includes?("forward") && @stale_forward_return_calls == 0
      @stale_forward_return_calls += 1
      return Adamas::HIR::TypeRef::INT32
    end
    super
  end

  private def lower_function_if_needed(name : String, trace_site_line : Int32 = __LINE__) : Nil
    if ENV["ADAMAS_TEST_DEFER_FORWARD_RAW_CALLBACK"]? == "1" &&
       name.includes?("forward") && name.includes?("__rawcb_")
      set_function_state(name, Adamas::HIR::AstToHir::FunctionLoweringState::Pending)
      enqueue_pending_function(name, "test_deferred_raw_callback")
      return
    end
    super
  end
end

private def lower_stale_raw_callback_program(code : String) : StaleRawCallbackReturnAstToHir
  arena, exprs = raw_callback_parse(code)
  converter = StaleRawCallbackReturnAstToHir.new(arena)
  converter.arena = arena

  def_nodes = exprs.compact_map do |expr_id|
    arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
  end
  def_nodes.each { |node| converter.register_function(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter
end

class Adamas::HIR::AstToHir
  def __test_lowered_raw_callback_target_return_type(name : String) : Adamas::HIR::TypeRef?
    lowered_raw_callback_target_return_type(name)
  end

  def __test_raw_callback_proc_contract_present?(type : Adamas::HIR::TypeRef) : Bool
    !!raw_callback_abi_for_proc_type(type)
  end
end

describe "raw callback ABI late contract" do
  it "uses the lowered alias Function return for the emitted Call" do
    previous_disable_inline = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
    ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
    converter = begin
      lower_stale_raw_callback_program(<<-CRYSTAL)
      def produce(flag : Bool) : Int32 | Int64
        flag ? 7 : 4294967296_i64
      end

      def dispatch(value : Int32 | Int64, &block) : Bool
        yield value
        true
      end

      def caller(flag : Bool) : Bool
        first = dispatch(produce(flag)) do |value|
          value.is_a?(Int64) ? value + 1_i64 : 99_i64
        end
        second = dispatch(produce(flag)) do |value|
          value.is_a?(Int64) ? value + 2_i64 : 98_i64
        end
        first && second
      end
      CRYSTAL
    ensure
      if previous_disable_inline
        ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous_disable_inline
      else
        ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
      end
    end

    caller_function = converter.module.functions.find do |function|
      function.name.starts_with?("caller")
    end
    caller_function.should_not be_nil
    calls = caller_function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end
    callback_call = calls.find { |call| call.method_name.includes?("dispatch") && call.method_name.includes?("__rawcb_") }
    callback_call.should_not be_nil
    alias_function = converter.module.function_by_name(callback_call.not_nil!.method_name)
    alias_function.should_not be_nil
    alias_function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::BOOL)
    raw_aliases = converter.module.functions.select do |function|
      function.name.includes?("dispatch") && function.name.includes?("__rawcb_")
    end
    raw_aliases.size.should eq(2)
    first_shape = callback_call.not_nil!.method_name.index("__rawcb_")
    first_shape.should_not be_nil
    callback_call.not_nil!.method_name.byte_slice(first_shape.not_nil! + 8).should contain("__rawcb_")
    callback_call = calls.find { |call| call.method_name == alias_function.not_nil!.name }
    callback_call.should_not be_nil
    callback_call.not_nil!.type.should eq(alias_function.not_nil!.return_type)
  end

  it "refreshes a yield-forwarding Call after the actual callback shape differs" do
    previous_disable_inline = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
    previous_stale_forward_return = ENV["ADAMAS_TEST_STALE_FORWARD_RETURN"]?
    ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
    ENV["ADAMAS_TEST_STALE_FORWARD_RETURN"] = "1"
    converter = begin
      lower_stale_raw_callback_program(<<-CRYSTAL)
      def produce(flag : Bool) : Int32 | Int64
        flag ? 7 : 4294967296_i64
      end

      def forward(value : Int32 | Int64, &block) : Int64
        yield value
      end

      def forward_caller(flag : Bool) : Int64
        forward(produce(flag)) do |value|
          value.is_a?(Int64) ? value + 1_i64 : 99_i64
        end
      end
      CRYSTAL
    ensure
      if previous_disable_inline
        ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous_disable_inline
      else
        ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
      end
      if previous_stale_forward_return
        ENV["ADAMAS_TEST_STALE_FORWARD_RETURN"] = previous_stale_forward_return
      else
        ENV.delete("ADAMAS_TEST_STALE_FORWARD_RETURN")
      end
    end

    caller_function = converter.module.functions.find do |function|
      function.name.starts_with?("forward_caller")
    end
    caller_function.should_not be_nil
    callback_call = caller_function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end.find { |call| call.method_name.includes?("forward") && call.method_name.includes?("__rawcb_") }
    callback_call.should_not be_nil
    alias_function = converter.module.function_by_name(callback_call.not_nil!.method_name)
    alias_function.should_not be_nil
    alias_function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT64)
    callback_call.not_nil!.type.should eq(alias_function.not_nil!.return_type)
  end

  it "keeps a registered late alias pending when body lowering is deferred" do
    previous_disable_inline = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
    previous_stale_forward_return = ENV["ADAMAS_TEST_STALE_FORWARD_RETURN"]?
    previous_defer_raw_callback = ENV["ADAMAS_TEST_DEFER_FORWARD_RAW_CALLBACK"]?
    ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
    ENV["ADAMAS_TEST_STALE_FORWARD_RETURN"] = "1"
    ENV["ADAMAS_TEST_DEFER_FORWARD_RAW_CALLBACK"] = "1"
    converter = begin
      lower_stale_raw_callback_program(<<-CRYSTAL)
      def produce(flag : Bool) : Int32 | Int64
        flag ? 7 : 4294967296_i64
      end

      def forward(value : Int32 | Int64, &block) : Int64
        yield value
      end

      def forward_caller(flag : Bool) : Int64
        forward(produce(flag)) do |value|
          value.is_a?(Int64) ? value + 1_i64 : 99_i64
        end
      end
      CRYSTAL
    ensure
      if previous_disable_inline
        ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous_disable_inline
      else
        ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
      end
      if previous_stale_forward_return
        ENV["ADAMAS_TEST_STALE_FORWARD_RETURN"] = previous_stale_forward_return
      else
        ENV.delete("ADAMAS_TEST_STALE_FORWARD_RETURN")
      end
      if previous_defer_raw_callback
        ENV["ADAMAS_TEST_DEFER_FORWARD_RAW_CALLBACK"] = previous_defer_raw_callback
      else
        ENV.delete("ADAMAS_TEST_DEFER_FORWARD_RAW_CALLBACK")
      end
    end

    caller_function = converter.module.functions.find do |function|
      function.name.starts_with?("forward_caller")
    end
    caller_function.should_not be_nil
    callback_call = caller_function.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end.find { |call| call.method_name.includes?("forward") && call.method_name.includes?("__rawcb_") }
    callback_call.should_not be_nil
    alias_name = callback_call.not_nil!.method_name
    converter.module.function_by_name(alias_name).should be_nil
    callback_call.not_nil!.type.should eq(Adamas::HIR::TypeRef::VOID)

    converter.flush_pending_functions
    alias_function = converter.module.function_by_name(alias_name)
    alias_function.should_not be_nil
    alias_function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT64)
    repaired_call = converter.module.functions.find do |function|
      function.name.starts_with?("forward_caller")
    end.not_nil!.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::Call)
    end.find { |call| call.method_name == alias_name }
    repaired_call.should_not be_nil
    repaired_call.not_nil!.type.should eq(alias_function.not_nil!.return_type)
  end

  it "does not certify a missing lowered callback target" do
    arena, _ = raw_callback_parse("1")
    converter = Adamas::HIR::AstToHir.new(arena)
    converter.__test_lowered_raw_callback_target_return_type("__missing_raw_callback_target").should be_nil
    converter.module.create_function("__pending_raw_callback_target", Adamas::HIR::TypeRef::INT64)
    converter.__test_lowered_raw_callback_target_return_type("__pending_raw_callback_target").should eq(Adamas::HIR::TypeRef::INT64)
    converter.module.create_function("__void_raw_callback_target", Adamas::HIR::TypeRef::VOID)
    converter.__test_lowered_raw_callback_target_return_type("__void_raw_callback_target").should be_nil
  end

  it "rejects missing or non-concrete Proc callback descriptors" do
    arena, _ = raw_callback_parse("1")
    converter = Adamas::HIR::AstToHir.new(arena)
    void_proc = converter.module.intern_type(
      Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Proc,
        "Proc",
        [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::VOID],
      )
    )
    nil_proc = converter.module.intern_type(
      Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Proc,
        "Proc",
        [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::NIL],
      )
    )
    non_proc = Adamas::HIR::TypeRef::INT32
    converter.__test_raw_callback_proc_contract_present?(void_proc).should be_false
    converter.__test_raw_callback_proc_contract_present?(nil_proc).should be_true
    converter.__test_raw_callback_proc_contract_present?(non_proc).should be_false
  end
end
