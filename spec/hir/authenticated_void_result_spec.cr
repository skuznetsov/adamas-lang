require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_void_materialize(name : String) : Adamas::HIR::Function
    lower_function_if_needed(name)
    @module.function_by_name(name) || raise "missing body #{name}"
  end

  def __test_void_incomplete_mem(function : Adamas::HIR::Function) : Nil
    context = Adamas::HIR::LoweringContext.new(function, @module, @arena)
    value = emit_mem_intrinsic(context, "memset", [] of ValueId)
    function.get_block(function.entry_block).terminator = Adamas::HIR::Return.new(value)
  end

  def __test_void_result_settled?(name : String) : Bool
    exact_callsite_return_contract_materialized?(name)
  end

  def __test_void_result_pending(name : String, provisional : Bool) : Nil
    if provisional
      @force_lower_provisional_dependencies[name] = Set{ "unresolved_producer" }
    else
      set_function_state(name, FunctionLoweringState::Pending)
    end
  end

  def __test_void_source_stale(name : String, arena : Bool) : Nil
    if arena
      @function_def_arenas[name] = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new("nil")).parse_program.arena
    else
      @function_defs[name] = @function_defs["scalar_leaf"]
    end
  end
end

private def void_result_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    lib VoidResultOracle
      fun srand(seed : UInt32) : Void
    end
    def void_leaf
      VoidResultOracle.srand(1_u32)
    end
    def void_caller
      void_leaf
    end
    def discard_leaf : Void
      123
    end
    def scalar_leaf
      123
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?
  converter = Adamas::HIR::AstToHir.new(parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  parsed.roots.each do |root|
    case node = parsed.arena[root]
    when Adamas::Compiler::Frontend::LibNode
      converter.register_lib(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    end
  end
  converter
end

private def replace_void_return(function : Adamas::HIR::Function, value : Adamas::HIR::Value) : Nil
  block = function.get_block(function.entry_block)
  block.add(value)
  block.terminator = Adamas::HIR::Return.new(value.id)
end

describe "authenticated completed Void results" do
  it "distinguishes a completed declared C Void result from an unmaterialized source" do
    converter = void_result_converter
    converter.__test_void_result_settled?("void_leaf").should be_false
    function = converter.__test_void_materialize("void_leaf")
    function.return_type.should eq(Adamas::HIR::TypeRef::VOID)
    converter.__test_void_result_settled?("void_leaf").should be_true
  end

  it "settles a source caller of an authenticated Void body" do
    converter = void_result_converter
    converter.__test_void_materialize("void_caller")
    converter.__test_void_result_settled?("void_leaf").should be_true
    converter.__test_void_result_settled?("void_caller").should be_true
  end

  it "admits a resolved explicit Void discard without inventing a return value" do
    converter = void_result_converter
    function = converter.__test_void_materialize("discard_leaf")
    function.source_return_discard_type.should eq(Adamas::HIR::TypeRef::VOID)
    if function.return_type == Adamas::HIR::TypeRef::VOID
      function.blocks.any? { |block| block.terminator.as?(Adamas::HIR::Return).try(&.value) }.should be_false
    else
      # Source calls to :Void can use the Nil expression carrier. Preserve
      # the existing distinction instead of requiring an ABI rewrite here.
      function.return_type.should eq(Adamas::HIR::TypeRef::NIL)
    end
    converter.__test_void_result_settled?("discard_leaf").should be_true
  end

  [false, true].each do |provisional|
    it "rejects a completed-looking body while #{provisional ? "provisional dependencies remain" : "its state is pending"}" do
      converter = void_result_converter
      converter.__test_void_materialize("void_leaf")
      converter.__test_void_result_pending("void_leaf", provisional)
      converter.__test_void_result_settled?("void_leaf").should be_false
    end
  end

  [false, true].each do |arena|
    it "rejects stale #{arena ? "arena" : "Def"} ownership" do
      converter = void_result_converter
      converter.__test_void_materialize("void_leaf")
      converter.__test_void_source_stale("void_leaf", arena)
      converter.__test_void_result_settled?("void_leaf").should be_false
    end
  end

  it "does not accept an unresolved Void carrier with published source facts" do
    converter = void_result_converter
    function = converter.__test_void_materialize("scalar_leaf")
    function.return_type = Adamas::HIR::TypeRef::VOID
    function.source_return_value_facts = [{Adamas::HIR::TypeRef::VOID, false}]
    replace_void_return(function, Adamas::HIR::Literal.new(function.next_value_id, Adamas::HIR::TypeRef::VOID, nil))
    converter.__test_void_result_settled?("scalar_leaf").should be_false
  end

  [nil, Adamas::HIR::TypeRef::INT32].each do |declared_type|
    it "rejects a Void extern carrier with #{declared_type ? "a conflicting" : "no resolved"} declaration" do
      converter = void_result_converter
      function = converter.__test_void_materialize("void_leaf")
      extern = Adamas::HIR::ExternCall.new(function.next_value_id, Adamas::HIR::TypeRef::VOID,
        "srand", declared_return_type: declared_type)
      replace_void_return(function, extern)
      converter.__test_void_result_settled?("void_leaf").should be_false
    end
  end

  it "rejects a NoReturn declaration even when its ABI carrier is Void" do
    converter = void_result_converter
    function = converter.__test_void_materialize("void_leaf")
    extern = Adamas::HIR::ExternCall.new(function.next_value_id, Adamas::HIR::TypeRef::VOID,
      "abort", noreturn: true, declared_return_type: Adamas::HIR::TypeRef::VOID)
    replace_void_return(function, extern)
    converter.__test_void_result_settled?("void_leaf").should be_false
  end

  it "rechecks the current producer graph after source facts have been published" do
    converter = void_result_converter
    function = converter.__test_void_materialize("void_leaf")
    converter.__test_void_result_settled?("void_leaf").should be_true
    call = Adamas::HIR::Call.new(function.next_value_id, Adamas::HIR::TypeRef::VOID, "missing_producer")
    replace_void_return(function, call)
    converter.__test_void_result_settled?("void_leaf").should be_false
  end

  it "does not authenticate the legacy incomplete memory-intrinsic fallback" do
    converter = void_result_converter
    function = converter.__test_void_materialize("void_leaf")
    converter.__test_void_incomplete_mem(function)
    converter.__test_void_result_settled?("void_leaf").should be_false
  end

  it "fails closed on a recursive result-proof cycle" do
    converter = void_result_converter
    function = converter.__test_void_materialize("void_leaf")
    call = Adamas::HIR::Call.new(function.next_value_id, Adamas::HIR::TypeRef::VOID, "void_leaf")
    replace_void_return(function, call)
    converter.__test_void_result_settled?("void_leaf").should be_false
  end

  it "does not substitute a virtual contract for a concrete result body" do
    converter = void_result_converter
    converter.__test_void_materialize("void_leaf")
    function = converter.__test_void_materialize("void_caller")
    call = Adamas::HIR::Call.without_receiver_virtual(function.next_value_id,
      Adamas::HIR::TypeRef::VOID, "void_leaf", [] of Adamas::HIR::ValueId, true)
    replace_void_return(function, call)
    converter.__test_void_result_settled?("void_caller").should be_false
  end
end
