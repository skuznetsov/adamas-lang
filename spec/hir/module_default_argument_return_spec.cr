require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_module_default_return_type(expression : Adamas::Compiler::Frontend::ExprId)
    infer_type_from_expr(expression, nil)
  end
end

private def infer_module_default_return(expression : String, definition : String = "def self.value(value = 42); value; end")
  source = <<-CRYSTAL
    module DefaultReturn
      #{definition}
    end
    #{expression}
    CRYSTAL
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)).parse_program
  converter = Adamas::HIR::AstToHir.new(
    parsed.arena, sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  owner = parsed.arena[parsed.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
  converter.register_module(owner)
  converter.lower_module(owner)
  converter.__test_module_default_return_type(parsed.roots.last)
end

private def lower_module_default_calls(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(
    parsed.arena, sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  converter.arena = parsed.arena
  main_exprs = [] of UInt64
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  parsed.roots.each do |root_id|
    next unless root_id
    case node = parsed.arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
      converter.register_module(node)
    else
      main_exprs << root_id.index.to_u64
    end
  end
  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main_exprs)
end

private def module_default_call_types(function : Adamas::HIR::Function) : Array(Adamas::HIR::TypeRef)
  result = [] of Adamas::HIR::TypeRef
  function.blocks.each do |block|
    block.instructions.each do |instruction|
      next unless call = instruction.as?(Adamas::HIR::Call)
      next unless call.method_name.starts_with?("DeferredModule.defaulted")
      result << call.type
    end
  end
  result
end

describe "module default argument return inference" do
  it "uses the default type for a call without parentheses" do
    infer_module_default_return("DefaultReturn.value").should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "uses the default type for a call with parentheses" do
    infer_module_default_return("DefaultReturn.value()").should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "uses an actual argument instead of its default's type" do
    infer_module_default_return("DefaultReturn.value(7_i64)").should eq(Adamas::HIR::TypeRef::INT64)
  end

  it "uses a named actual instead of its default's type" do
    infer_module_default_return("DefaultReturn.value(value: 7_i64)").should eq(Adamas::HIR::TypeRef::INT64)
  end

  it "does not infer through a named call shape shared by distinct overloads" do
    source = <<-CRYSTAL
      module DefaultReturn
        def self.value(value : Int32)
          value
        end
        def self.value(value : String)
          value
        end
      end
      DefaultReturn.value(value: 7)
      CRYSTAL
    parsed = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source)).parse_program
    converter = Adamas::HIR::AstToHir.new(
      parsed.arena, sources_by_arena: {parsed.arena.object_id.to_u64 => source},
    )
    owner = parsed.arena[parsed.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
    converter.register_module(owner)
    converter.lower_module(owner)
    converter.__test_module_default_return_type(parsed.roots.last).should be_nil
  end

  it "does not replace an unknown actual with the default" do
    infer_module_default_return("DefaultReturn.value(unknown)").should be_nil
  end

  it "makes an earlier default visible to a later default" do
    infer_module_default_return("DefaultReturn.value",
      "def self.value(first = 42, second = first); second; end").should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "makes an earlier actual visible to a later default" do
    infer_module_default_return("DefaultReturn.value(7_i64)",
      "def self.value(first = 42, second = first); second; end").should eq(Adamas::HIR::TypeRef::INT64)
  end

  it "preserves a defaulted module call's value through bare and grouped puts" do
    source = <<-CRYSTAL
      module DeferredModule
        def self.defaulted(value = 42) : Int32
          value
        end
      end
      puts DeferredModule.defaulted
      puts(DeferredModule.defaulted)
      CRYSTAL
    main = lower_module_default_calls(source)
    text = main.to_s
    text.should contain("DeferredModule.defaulted")
    # Int32 puts may lower directly to the primitive print extern instead of
    # materializing a puts method call. The relevant contract is that the
    # inferred defaulted call remains Int32 through that output consumer.
    text.should contain("__adamas_print_int32_ln")
    text.should contain(": 4")
    text.should_not contain("puts$Tuple(Void)")
  end

  it "keeps inferred default-call returns through bare, grouped, and explicit calls" do
    source = <<-CRYSTAL
      module DeferredModule
        def self.defaulted(value = 42)
          value
        end
      end
      puts DeferredModule.defaulted
      puts(DeferredModule.defaulted)
      puts DeferredModule.defaulted()
      CRYSTAL
    main = lower_module_default_calls(source)
    text = main.to_s
    text.should contain("DeferredModule.defaulted")
    text.should contain("call DeferredModule.defaulted$Int32(")
    text.should contain("__adamas_print_int32_ln")
    text.should contain(": 4")
    text.should_not contain("puts$Tuple(Void)")
    # The bare and grouped forms use the unsuffixed default target; explicit
    # parentheses select the concrete zero-argument default specialization.
    (text.split("call DeferredModule.defaulted(").size - 1).should eq(2)
    call_types = module_default_call_types(main)
    call_types.size.should eq(3)
    call_types.each { |call_type| call_type.should eq(Adamas::HIR::TypeRef::INT32) }
  end

  it "publishes the inferred return before lowering the first default-only call" do
    source = <<-CRYSTAL
      module DeferredModule
        def self.defaulted(value = 42)
          value
        end
      end
      puts DeferredModule.defaulted
      puts(DeferredModule.defaulted)
      CRYSTAL
    main = lower_module_default_calls(source)
    call_types = module_default_call_types(main)
    call_types.should_not be_empty
    call_types.each do |call_type|
      call_type.should eq(Adamas::HIR::TypeRef::INT32)
    end
  end
end
