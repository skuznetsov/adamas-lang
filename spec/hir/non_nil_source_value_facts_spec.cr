require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_non_nil_source_facts(
    union_name : String,
    source_facts : Array({String, Bool}),
    to_branch : Bool,
  )
    source_type = create_union_type(union_name)
    function = @module.create_function("__non_nil_source_facts_#{to_branch}", TypeRef::VOID)
    param = function.add_param("value", source_type)
    ctx = LoweringContext.new(function, @module, @arena)
    ctx.register_type(param.id, source_type)
    input_facts = source_facts.map { |(name, literal)| {type_ref_for_name(name), literal} }
    ctx.register_source_value_facts(param.id, input_facts)
    before_facts = ctx.source_value_facts(param.id).not_nil!.dup
    narrowed = if to_branch
                 target = function.create_block(function.get_block(function.entry_block).scope)
                 unwrap_non_nil_to_block(ctx, target, param.id, source_type)
               else
                 lower_not_nil_intrinsic(ctx, param.id, source_type)
               end
    named = ctx.source_value_facts(narrowed).try do |facts|
      facts.map { |(type, literal)| "#{generic_param_type_name_from_ref(type)}:#{literal}" }.sort
    end
    {
      source_name: generic_param_type_name_from_ref(source_type),
      changed: narrowed != param.id,
      producer: ctx.value_for(narrowed).try(&.class.name),
      facts: named,
      source_unchanged: ctx.source_value_facts(param.id) == before_facts,
      literal: ctx.type_literal?(narrowed),
    }
  end

  def __test_non_nil_unknown_source_facts(
    union_name : String,
    producer_shape : String,
    to_branch : Bool,
  )
    source_type = create_union_type(union_name)
    function = @module.create_function("__non_nil_unknown_source_facts_#{producer_shape}_#{to_branch}", TypeRef::VOID)
    ctx = LoweringContext.new(function, @module, @arena)
    unknown_call = ctx.emit(Call.without_receiver(ctx.next_id, source_type, "unknown_source", [] of ValueId))
    source = if producer_shape == "phi_with_unknown_leaf"
               known_param = function.add_param("known", type_ref_for_name("NonNilFactsA"))
               ctx.register_type(known_param.id, known_param.type)
               ctx.mark_type_literal(known_param.id)
               Phi.new(
                 ctx.next_id,
                 source_type,
                 [{ctx.current_block_id, unknown_call.id}, {ctx.current_block_id, known_param.id}],
               ).tap { |phi| ctx.emit(phi) }
             else
               unknown_call
             end
    source_id = source.id
    narrowed = if to_branch
                 target = function.create_block(function.get_block(function.entry_block).scope)
                 unwrap_non_nil_to_block(ctx, target, source_id, source_type)
               else
                 lower_not_nil_intrinsic(ctx, source_id, source_type)
               end
    named = ctx.source_value_facts(narrowed).try do |facts|
      facts.map { |(type, literal)| {generic_param_type_name_from_ref(type), literal} }.sort_by { |(name, literal)| {name, literal ? 1 : 0} }
    end
    {
      source_name: generic_param_type_name_from_ref(source_type),
      changed: narrowed != source_id,
      producer: ctx.value_for(narrowed).try(&.class.name),
      facts: named,
      source_facts: ctx.source_value_facts(source_id),
      literal: ctx.type_literal?(narrowed),
    }
  end
end

private def non_nil_source_facts_converter
  source = "class NonNilFactsA; end; class NonNilFactsB; end"
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  converter.no_prelude = true
  parsed.roots.each do |root|
    if node = parsed.arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end
  converter
end

describe "non-nil narrowing source facts" do
  [false, true].each do |to_branch|
    it "owns reference-union facts on its new SSA result (branch=#{to_branch})" do
      result = non_nil_source_facts_converter.__test_non_nil_source_facts(
        "NonNilFactsA | NonNilFactsB | Nil",
        [{"NonNilFactsA | NonNilFactsB | Nil", false}], to_branch,
      )
      result[:changed].should be_true
      result[:producer].should eq("Adamas::HIR::Copy")
      result[:facts].should eq(["NonNilFactsA:false", "NonNilFactsB:false"])
      result[:source_unchanged].should be_true
    end

    it "owns value-union remap facts (branch=#{to_branch})" do
      result = non_nil_source_facts_converter.__test_non_nil_source_facts(
        "Int32 | UInt32 | Nil", [{"Int32 | UInt32 | Nil", false}], to_branch,
      )
      result[:changed].should be_true
      result[:producer].should eq("Adamas::HIR::UnionWrap")
      result[:facts].should eq(["Int32:false", "UInt32:false"])
      result[:source_unchanged].should be_true
    end

    it "keeps class alternatives including truthy Nil.class (branch=#{to_branch})" do
      result = non_nil_source_facts_converter.__test_non_nil_source_facts(
        "NonNilFactsA | NonNilFactsB | Nil",
        [{"NonNilFactsA", false}, {"NonNilFactsB", true}, {"Nil", true}, {"Nil", false}],
        to_branch,
      )
      result[:facts].should eq(["Nil:true", "NonNilFactsA:false", "NonNilFactsB:true"])
      result[:literal].should be_false
      result[:source_unchanged].should be_true
    end

    it "retains singleton class kind on UnionUnwrap (branch=#{to_branch})" do
      result = non_nil_source_facts_converter.__test_non_nil_source_facts(
        "NonNilFactsA | Nil", [{"NonNilFactsA", true}, {"Nil", false}], to_branch,
      )
      result[:changed].should be_true
      result[:producer].should eq("Adamas::HIR::UnionUnwrap")
      result[:facts].should eq(["NonNilFactsA:true"])
      result[:literal].should be_true
      result[:source_unchanged].should be_true
    end

    it "retains a directly grounded Void class fact (branch=#{to_branch})" do
      result = non_nil_source_facts_converter.__test_non_nil_source_facts(
        "NonNilFactsA | NonNilFactsB | Nil",
        [{"NonNilFactsA", false}, {"Void", true}, {"Nil", false}], to_branch,
      )
      result[:facts].should eq(["NonNilFactsA:false", "Void:true"])
      result[:source_unchanged].should be_true
    end

    it "retains both source kinds when the original source proof is empty (branch=#{to_branch})" do
      result = non_nil_source_facts_converter.__test_non_nil_source_facts(
        "NonNilFactsA | Nil", [] of {String, Bool}, to_branch,
      )
      result[:facts].should eq(["#{result[:source_name]}:false", "#{result[:source_name]}:true"])
      result[:literal].should be_false
      result[:source_unchanged].should be_true
    end

    it "keeps the unrefined proof when removing Nil leaves no alternatives (branch=#{to_branch})" do
      result = non_nil_source_facts_converter.__test_non_nil_source_facts(
        "NonNilFactsA | NonNilFactsB | Nil", [{"Nil", false}], to_branch,
      )
      result[:changed].should be_true
      result[:facts].should eq(["Nil:false"])
      result[:source_unchanged].should be_true
    end
  end

  [false, true].each do |to_branch|
    ["NonNilFactsA | Nil", "NonNilFactsA | NonNilFactsB | Nil"].each do |carrier|
      ["call_leaf", "phi_with_unknown_leaf"].each do |shape|
        # An unregistered union leaf is an instance of its carrier, as in
        # source_block_result_value_facts. Narrowing must only remove Nil from
        # that set; it must not add `Nil` back or invent `T.class` arms.
        it "narrows an unregistered union leaf as carrier instances for #{shape} (carrier=#{carrier}, branch=#{to_branch})" do
          result = non_nil_source_facts_converter.__test_non_nil_unknown_source_facts(
            carrier, shape, to_branch,
          )
          result[:changed].should be_true
          result[:producer].should eq(carrier.includes?("NonNilFactsB") ? "Adamas::HIR::Copy" : "Adamas::HIR::UnionUnwrap")
          expected = [{"NonNilFactsA", false}]
          expected << {"NonNilFactsA", true} if shape == "phi_with_unknown_leaf"
          expected << {"NonNilFactsB", false} if carrier.includes?("NonNilFactsB")
          result[:facts].should eq(expected.sort_by { |(name, literal)| {name, literal ? 1 : 0} })
          result[:source_facts].should be_nil
          result[:literal].should be_false
        end
      end
    end
  end
end
