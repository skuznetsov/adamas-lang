require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

private def lower_loop_exit_binding_fixture : Adamas::HIR::Function
  source = <<-CRYSTAL
    def stale_lower_super(owner : Bool, module_hit : Bool, callable : Bool, fallback : String) : String
      x : String? = nil
      probe_owner = owner
      while probe_owner
        if module_hit
          probe_owner = false
          next
        end
        candidate = "candidate"
        if callable
          x = candidate
          break
        end
        probe_owner = false
      end
      unless x
        x = fallback
      end
      x.not_nil!
    end
  CRYSTAL

  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  arena = result.arena
  def_expr = result.roots.find { |expr_id| arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode) }
  raise "loop-exit binding fixture did not parse a function" unless def_expr
  def_node = arena[def_expr.not_nil!].as(Adamas::Compiler::Frontend::DefNode)
  Adamas::HIR::AstToHir.new(arena).lower_def(def_node)
end

private def hir_value(function : Adamas::HIR::Function, value_id : Adamas::HIR::ValueId) : Adamas::HIR::Value?
  function.blocks.each do |block|
    block.instructions.each do |instruction|
      return instruction if instruction.id == value_id
    end
  end
  nil
end

private def hir_block_for_value(function : Adamas::HIR::Function, value_id : Adamas::HIR::ValueId) : Adamas::HIR::Block?
  function.blocks.each do |block|
    block.instructions.each do |instruction|
      return block if instruction.id == value_id
    end
  end
  nil
end

private def copy_root(function : Adamas::HIR::Function, value_id : Adamas::HIR::ValueId) : Adamas::HIR::Value
  current = value_id
  loop do
    value = hir_value(function, current)
    raise "HIR fixture references missing value #{current}" unless value
    copy = value.as?(Adamas::HIR::Copy)
    break value unless copy
    current = copy.source
  end
end

describe "loop-exit local binding" do
  it "uses the loop-exit phi for the post-loop nullable check" do
    function = lower_loop_exit_binding_fixture
    union_checks = function.blocks.flat_map(&.instructions).select(Adamas::HIR::UnionIs)
    union_checks.should_not be_empty

    union_roots = union_checks.map do |check|
      copy_root(function, check.union_value)
    end
    union_roots.each do |root|
      root.should be_a(Adamas::HIR::Phi)
      phi = root.as(Adamas::HIR::Phi)
      # The exit merge has at least normal-exit and break inputs. The
      # loop-header phi has a self backedge and must never feed this check.
      phi.incoming_size.should be >= 2
      phi.incoming_values.should_not contain(phi.id)
    end

    post_loop_check = union_checks.first
    post_loop_phi = union_roots.first.as(Adamas::HIR::Phi)
    post_loop_phi_block = hir_block_for_value(function, post_loop_phi.id)
    check_block = function.blocks.find { |block| block.instructions.includes?(post_loop_check) }
    post_loop_phi_block.should_not be_nil
    check_block.should_not be_nil
    post_loop_phi_block.not_nil!.id.should eq(check_block.not_nil!.id)

    unwraps = function.blocks.flat_map(&.instructions).select(Adamas::HIR::UnionUnwrap)
    unwraps.should_not be_empty
    unwraps.each do |unwrap|
      root = copy_root(function, unwrap.union_value)
      root.should be_a(Adamas::HIR::Phi)
      root.as(Adamas::HIR::Phi).id.should eq(post_loop_phi.id)
    end
  end
end
