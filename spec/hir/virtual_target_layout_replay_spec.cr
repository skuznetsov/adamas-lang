require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_invalidate_virtual_target_layout(owner : String) : Nil
    invalidate_lowered_layout_functions(owner)
  end

  def __test_virtual_layout_replay_pending?(name : String) : Bool
    function_state(name).pending?
  end

  def __test_virtual_layout_replay_exact_called?(name : String) : Bool
    @rta_called_methods.includes?(name)
  end

  def __test_virtual_layout_body_demanded?(name : String) : Bool
    @virtual_target_body_demands.includes?(name)
  end

  def __test_flush_virtual_layout_replay : Nil
    flush_pending_functions
  end

  def __test_demand_virtual_layout_target(root_kind : Symbol) : Nil
    args = [] of TypeRef
    if root_kind == :module
      lower_virtual_target_resolved("VirtualLayoutOwner", "value", args, false, false)
    elsif root_kind == :class
      lower_virtual_target_owner("VirtualLayoutOwner", "value", args, false, false)
    end
  end

  def __test_defer_uninstantiated_virtual_layout_target(name : String) : Int32
    initialize_lazy_rta
    @lazy_rta_active = true
    @virtual_target_body_demands << name
    @rta_deferred_functions << name
    @rta_deferred_set << name
    set_function_state(name, FunctionLoweringState::Pending)
    undefer_rta_functions
  end

  def __test_virtual_layout_deferred?(name : String) : Bool
    @rta_deferred_set.includes?(name)
  end

  def __test_make_virtual_layout_owner_live(owner : String) : Int32
    mark_live_type(owner)
    undefer_rta_functions
  end
end

private def virtual_target_layout_replay_fixture(root_kind : Symbol) : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    module VirtualLayoutContract
      abstract def value : Int32
    end
    class VirtualLayoutRoot
    end
    class VirtualLayoutOwner < VirtualLayoutRoot
      include VirtualLayoutContract
      getter value : Int32 = 41
    end
    VirtualLayoutOwner.new
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  main = [] of UInt64
  parsed.roots.each do |id|
    case node = parsed.arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      converter.lower_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  # Exercise the production fanout producer directly. Ordinary calls can be
  # devirtualized when their only argument has this one concrete runtime type.
  converter.__test_demand_virtual_layout_target(root_kind)
  converter
end

describe "virtual target replay after layout invalidation" do
  it "does not turn an unused generated getter into a lowering demand" do
    converter = virtual_target_layout_replay_fixture(:unused)
    name = "VirtualLayoutOwner#value"
    converter.module.has_function_with_body?(name).should be_true
    converter.module.virtual_dispatch_target_functions.should_not contain(name)
    converter.__test_invalidate_virtual_target_layout("VirtualLayoutOwner")
    converter.__test_virtual_layout_replay_pending?(name).should be_false
  end

  it "keeps a virtual target deferred until its concrete owner becomes live" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    name = "UninstantiatedVirtualLayoutOwner#value"
    converter.__test_defer_uninstantiated_virtual_layout_target(name).should eq(0)
    converter.__test_virtual_layout_deferred?(name).should be_true
    converter.module.has_function_with_body?(name).should be_false
    converter.__test_make_virtual_layout_owner_live("UninstantiatedVirtualLayoutOwner").should eq(1)
    converter.__test_virtual_layout_deferred?(name).should be_false
  end

  [:module, :class].each do |root_kind|
    it "retains a generated getter demanded through a #{root_kind} receiver" do
      converter = virtual_target_layout_replay_fixture(root_kind)
      name = "VirtualLayoutOwner#value"
      converter.module.has_function_with_body?(name).should be_true
      converter.__test_virtual_layout_body_demanded?(name).should be_true
      if root_kind == :module
        # Preserving a layout replay must not turn module-fanout candidates
        # into unconditional DCE roots when their owner was never constructed.
        converter.module.virtual_dispatch_target_functions.should_not contain(name)
      end
      # A virtual target is a durable requirement even when no direct call
      # happened to add this concrete symbol to the exact RTA call set.
      converter.__test_virtual_layout_replay_exact_called?(name).should be_false
      converter.__test_invalidate_virtual_target_layout("VirtualLayoutOwner")
      converter.module.has_function_with_body?(name).should be_false
      converter.__test_virtual_layout_replay_pending?(name).should be_true
      converter.__test_flush_virtual_layout_replay
      converter.module.has_function_with_body?(name).should be_true
      function = converter.module.function_by_name(name).not_nil!
      function.params.first.type.should eq(converter.class_info["VirtualLayoutOwner"].type_ref)
      function.blocks.flat_map(&.instructions).any? do |instruction|
        instruction.is_a?(Adamas::HIR::FieldGet) && instruction.field_name == "@value"
      end.should be_true
    end
  end
end
