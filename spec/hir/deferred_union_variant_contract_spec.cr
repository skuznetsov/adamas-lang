require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_deferred_union_calls : Array(Adamas::HIR::Call)
    @deferred_union_variant_contracts.map(&.call)
  end

  # Isolate admission from queue draining so neither overload has a body yet.
  # The portable regression covers ordinary CLI and inline-yield integration.
  def __test_admit_deferred_union_call : Nil
    receiver_type = type_ref_for_name("DeferredContractDispatcher")
    argument_type = type_ref_for_name("Int32 | String")
    function = @module.create_function("deferred_contract_caller", TypeRef::STRING)
    receiver = function.add_param("receiver", receiver_type)
    argument = function.add_param("argument", argument_type)
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.register_type(receiver.id, receiver.type)
    ctx.register_type(argument.id, argument.type)
    old_depth = @lowering_depth
    old_suppression = @suppress_force_lower_return_type_depth
    begin
      @lowering_depth = 1
      @suppress_force_lower_return_type_depth = 1
      result = try_emit_union_arg_dispatch(
        ctx, receiver.id, "DeferredContractDispatcher#concat", nil,
        [argument.id], [argument_type], TypeRef::STRING,
        false, false, false, false, require_source_compatible_variants: true,
      )
      result.should_not be_nil
    ensure
      @lowering_depth = old_depth
      @suppress_force_lower_return_type_depth = old_suppression
    end
  end

end

private def lower_deferred_union_contract_fixture : Adamas::HIR::AstToHir
  code = <<-CRYSTAL
    class DeferredContractDispatcher
      private def concat(value : String)
        "string"
      end
      private def concat(value : Int32)
        "integer"
      end
      def fetch(flag : Bool, &)
        value = flag ? "entry" : 7
        concat(value)
      end
      def read(flag : Bool)
        fetch(flag) { "unused" }
      end
    end
    DeferredContractDispatcher.new.read(true)
    DeferredContractDispatcher.new.read(false)
  CRYSTAL
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  ).parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  result.roots.each do |id|
    node = result.arena[id]
    converter.register_class(node) if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
  end
  converter.__test_admit_deferred_union_call
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter.__test_deferred_union_calls.size.should be > 0
  converter.validate_deferred_union_variant_contracts!(converter.module)
  converter
end

describe "deferred exact union target contracts" do
  it "validates the materialized bodies of source-admitted scalar arms" do
    converter = lower_deferred_union_contract_fixture
    calls = converter.__test_deferred_union_calls
    calls.map(&.method_name).uniq.sort.should eq([
      "DeferredContractDispatcher#concat$Int32",
      "DeferredContractDispatcher#concat$String",
    ])
    calls.each do |call|
      target = converter.module.function_by_name(call.method_name).not_nil!
      target.blocks.any?(&.body_emitted).should be_true
      target.return_type.should eq(call.type)
    end
  end

  it "rejects a materialized target return that no longer matches the call" do
    converter = lower_deferred_union_contract_fixture
    call = converter.__test_deferred_union_calls.first
    target = converter.module.function_by_name(call.method_name).not_nil!
    target.return_type = Adamas::HIR::TypeRef::INT64
    expect_raises(Adamas::HIR::LoweringError, /deferred union target ABI changed/) do
      converter.validate_deferred_union_variant_contracts!(converter.module)
    end
  end

  it "rejects a call retargeted after source admission" do
    converter = lower_deferred_union_contract_fixture
    call = converter.__test_deferred_union_calls.first
    call.method_name = "DeferredContractDispatcher#concat$Missing"
    expect_raises(Adamas::HIR::LoweringError, /deferred union call identity changed/) do
      converter.validate_deferred_union_variant_contracts!(converter.module)
    end
  end
end
