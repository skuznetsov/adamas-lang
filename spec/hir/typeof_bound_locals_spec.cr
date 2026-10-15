require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_typeof_bound_receiver(node : Adamas::Compiler::Frontend::TypeofNode,
                                  receiver_name : String,
                                  boxed : Bool = false,
                                  stale_box : Bool = false)
    receiver_type = type_ref_for_name(receiver_name)
    function = @module.create_function("typeof_bound_probe_#{@module.functions.size}", TypeRef::NIL)
    carrier = function.add_param("stream", boxed && !stale_box ? TypeRef::POINTER : receiver_type)
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.register_type(carrier.id, carrier.type)
    ctx.register_local("stream", carrier.id)
    if boxed
      owner = stale_box ? function.add_param("unrelated", TypeRef::POINTER).id : carrier.id
      payload = stale_box ? type_ref_for_name("BoundTypeofReceiver(Int32)") : receiver_type
      ctx.register_boxed_local("stream", carrier.id, payload, owner)
    end
    result = lower_typeof(ctx, node)
    {get_type_name_from_ref(ctx.runtime_type_identity?(result).not_nil!.semantic_type), function}
  end

  def __test_typeof_scope_restoration(node : Adamas::Compiler::Frontend::TypeofNode)
    old_locals = @current_typeof_locals
    old_names = @current_typeof_local_names
    old_version = @infer_type_cache_version
    __test_typeof_bound_receiver(node, "BoundTypeofReceiver(Int32)")
    {@current_typeof_locals == old_locals, @current_typeof_local_names == old_names,
     @infer_type_cache_version == old_version}
  end
end

private def new_bound_typeof_probe
  source = <<-CRYSTAL
    class BoundTypeofReceiver(T)
      def receive : T
        42
      end
    end
    typeof(stream.receive)
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  klass = parsed.arena[parsed.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
  converter.register_class(klass)
  converter.lower_class(klass)
  node = parsed.arena[parsed.roots.last].as(Adamas::Compiler::Frontend::TypeofNode)
  {converter, node}
end

describe "semantic typeof of active HIR local bindings" do
  it "infers a nested operation from an already-bound local without a source body" do
    converter, node = new_bound_typeof_probe
    type, function = converter.__test_typeof_bound_receiver(node, "BoundTypeofReceiver(Int32)")
    type.should eq("Int32")
    function.blocks.flat_map(&.instructions).select(Adamas::HIR::Call).should be_empty
  end

  it "uses the payload type of an owner-matched captured local" do
    converter, node = new_bound_typeof_probe
    type, function = converter.__test_typeof_bound_receiver(node, "BoundTypeofReceiver(Int32)", boxed: true)
    type.should eq("Int32")
    function.blocks.flat_map(&.instructions).select(Adamas::HIR::FieldGet).should be_empty
    function.blocks.flat_map(&.instructions).select(Adamas::HIR::Call).should be_empty
  end

  it "does not borrow the payload of a shadowed same-name boxed binding" do
    converter, node = new_bound_typeof_probe
    type, _ = converter.__test_typeof_bound_receiver(node, "BoundTypeofReceiver(Int64)", boxed: true, stale_box: true)
    type.should eq("Int64")
  end

  it "does not reuse a receiver result from a previous local-type context" do
    converter, node = new_bound_typeof_probe
    first, _ = converter.__test_typeof_bound_receiver(node, "BoundTypeofReceiver(Int32)")
    second, _ = converter.__test_typeof_bound_receiver(node, "BoundTypeofReceiver(Int64)")
    first.should eq("Int32")
    second.should eq("Int64")
  end

  it "restores the ambient inference maps and cache epoch" do
    converter, node = new_bound_typeof_probe
    converter.__test_typeof_scope_restoration(node).should eq({true, true, true})
  end
end
