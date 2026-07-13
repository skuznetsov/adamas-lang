require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

private def lower_super_ancestor_fixture : {Adamas::HIR::AstToHir, Adamas::HIR::Function}
  source = <<-CRYSTAL
    module Stringifiable
      def stringify(flag : Bool, module_hit : Bool, stop : Bool, fallback : String) : String
        "Stringifiable"
      end
    end

    class Base2
      def stringify(flag : Bool, module_hit : Bool, stop : Bool, fallback : String) : String
        "Base2"
      end
    end

    class Mid2 < Base2
      include Stringifiable

      def stringify(flag : Bool, module_hit : Bool, stop : Bool, fallback : String) : String
        selected : String? = nil
        probe = flag
        while probe
          if module_hit
            probe = false
            next
          end
          selected = super
          if stop
            break
          end
          probe = false
        end
        unless selected
          selected = fallback
        end
        selected.not_nil!
      end
    end

    class Leaf2 < Mid2
      def stringify(flag : Bool, module_hit : Bool, stop : Bool, fallback : String) : String
        super
      end
    end
  CRYSTAL

  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  arena = result.arena
  converter = Adamas::HIR::AstToHir.new(arena)
  converter.arena = arena

  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  result.roots.each do |expr_id|
    case node = arena[expr_id]
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    end
  end

  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }
  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }

  function = converter.module.function_by_name("Mid2#stringify$Bool_Bool_Bool_String")
  raise "super ancestor fixture did not lower Mid2#stringify$Bool_Bool_Bool_String" unless function
  {converter, function.not_nil!}
end

private def super_fixture_value(function : Adamas::HIR::Function, value_id : Adamas::HIR::ValueId) : Adamas::HIR::Value?
  function.blocks.each do |block|
    block.instructions.each do |instruction|
      return instruction if instruction.id == value_id
    end
  end
  nil
end

private def super_fixture_block_for_value(function : Adamas::HIR::Function, value_id : Adamas::HIR::ValueId) : Adamas::HIR::Block?
  function.blocks.each do |block|
    block.instructions.each do |instruction|
      return block if instruction.id == value_id
    end
  end
  nil
end

private def super_fixture_copy_root(function : Adamas::HIR::Function, value_id : Adamas::HIR::ValueId) : Adamas::HIR::Value
  current = value_id
  loop do
    value = super_fixture_value(function, current)
    raise "super ancestor fixture references missing HIR value #{current}" unless value
    copy = value.as?(Adamas::HIR::Copy)
    break value unless copy
    current = copy.source
  end
end

private def super_fixture_copy_chain_reaches?(function : Adamas::HIR::Function, value_id : Adamas::HIR::ValueId, source_id : Adamas::HIR::ValueId) : Bool
  current = value_id
  loop do
    return true if current == source_id
    value = super_fixture_value(function, current)
    return false unless value
    copy = value.as?(Adamas::HIR::Copy)
    return false unless copy
    current = copy.source
  end
end

describe "source-level super ancestor loop binding" do
  it "resolves an included-module super target and keeps String? post-loop state" do
    converter, function = lower_super_ancestor_fixture
    expected_target = "Mid2#stringify_super_from_Stringifiable$Bool_Bool_Bool_String"
    calls = function.blocks.flat_map(&.instructions).select(Adamas::HIR::Call)
    super_call = calls.find { |call| call.method_name == expected_target }
    super_call.should_not be_nil
    super_call = super_call.not_nil!
    super_call.type.should eq(Adamas::HIR::TypeRef::STRING)
    super_call.receiver.should eq(function.params.first.id)
    super_call.args.should eq([function.params[1].id, function.params[2].id, function.params[3].id, function.params[4].id])

    target = converter.module.function_by_name(expected_target)
    target.should_not be_nil
    target_text = String.build { |io| target.not_nil!.to_s(io) }
    target_text.should contain("literal \"Stringifiable\"")

    leaf = converter.module.function_by_name("Leaf2#stringify$Bool_Bool_Bool_String")
    leaf.should_not be_nil
    leaf_super = leaf.not_nil!.blocks.flat_map(&.instructions).select(Adamas::HIR::Call).find do |call|
      call.method_name == "Mid2#stringify$Bool_Bool_Bool_String_super"
    end
    leaf_super.should_not be_nil

    instructions = function.blocks.flat_map(&.instructions)
    unwrap = instructions.find { |instruction| instruction.is_a?(Adamas::HIR::UnionUnwrap) }
    unwrap.should_not be_nil
    unwrap = unwrap.not_nil!.as(Adamas::HIR::UnionUnwrap)

    # Select the post-unless nullable check structurally, rather than taking
    # the first UnionIs in the function. Its root is the selected String? phi;
    # the Bool owner/probe header phi is deliberately excluded by type and by
    # the no-self-incoming invariant.
    union_check = instructions.select(Adamas::HIR::UnionIs).find do |check|
      root = super_fixture_copy_root(function, check.union_value)
      root.is_a?(Adamas::HIR::Phi) &&
        root.type != Adamas::HIR::TypeRef::BOOL &&
        root.as(Adamas::HIR::Phi).incoming_size >= 2 &&
        !root.as(Adamas::HIR::Phi).incoming_values.includes?(root.id)
    end
    union_check.should_not be_nil
    union_check = union_check.not_nil!
    super_fixture_copy_root(function, union_check.union_value).id.should eq(
      super_fixture_copy_root(function, unwrap.union_value).id
    )

    post_loop_root = super_fixture_copy_root(function, unwrap.union_value)
    post_loop_root.should be_a(Adamas::HIR::Phi)
    post_loop_phi = post_loop_root.as(Adamas::HIR::Phi)
    post_loop_phi.incoming_size.should eq(2)
    post_loop_phi.incoming_values.should_not contain(super_call.id)

    candidate_wrap = instructions.select(Adamas::HIR::UnionWrap).find do |wrap|
      wrap.variant_type_id != 0 && super_fixture_copy_root(function, wrap.value).id == super_call.id
    end
    candidate_wrap.should_not be_nil
    candidate_copy = instructions.select(Adamas::HIR::Copy).find { |copy| copy.source == super_call.id }
    candidate_copy.should_not be_nil
    post_loop_phi.incoming_values.should contain(candidate_copy.not_nil!.id)
    post_loop_phi.incoming_values.should_not contain(post_loop_phi.id)

    # The loop-header selected phi receives the wrapped candidate and carries
    # a self backedge; the post-loop phi selected above must instead receive
    # the break-path candidate copy and have no self incoming.
    owner_header_phi = instructions.select(Adamas::HIR::Phi).find do |phi|
      phi.incoming_values.includes?(candidate_wrap.not_nil!.id)
    end
    owner_header_phi.should_not be_nil
    owner_header_phi.not_nil!.incoming_values.should contain(owner_header_phi.not_nil!.id)

    fallback_param = function.params[4].id
    fallback_copies = instructions.select(Adamas::HIR::Copy).select do |copy|
      super_fixture_copy_chain_reaches?(function, copy.id, fallback_param)
    end
    fallback_copies.should_not be_empty
    fallback_wrap = instructions.select(Adamas::HIR::UnionWrap).find do |wrap|
      wrap.variant_type_id != 0 && super_fixture_copy_chain_reaches?(function, wrap.value, fallback_param)
    end
    fallback_wrap.should_not be_nil

    post_unless_value_phi = instructions.select(Adamas::HIR::Phi).find do |phi|
      phi.type == Adamas::HIR::TypeRef::STRING && phi.incoming_values.any? do |value_id|
        fallback_copies.any? { |copy| copy.id == value_id }
      end
    end
    post_unless_value_phi.should_not be_nil
    post_unless_union_phi = instructions.select(Adamas::HIR::Phi).find do |phi|
      phi.incoming_values.includes?(fallback_wrap.not_nil!.id)
    end
    post_unless_union_phi.should_not be_nil

    super_call_block = super_fixture_block_for_value(function, super_call.id)
    phi_block = super_fixture_block_for_value(function, post_loop_phi.id)
    super_call_block.should_not be_nil
    phi_block.should_not be_nil
    phi_block.not_nil!.id.should_not eq(super_call_block.not_nil!.id)

    return_value = function.blocks.flat_map do |block|
      terminator = block.terminator
      terminator.is_a?(Adamas::HIR::Return) ? terminator.value : nil
    end.compact.first?
    return_value.should_not be_nil
    super_fixture_copy_root(function, return_value.not_nil!).id.should eq(post_unless_value_phi.not_nil!.id)
  end
end
