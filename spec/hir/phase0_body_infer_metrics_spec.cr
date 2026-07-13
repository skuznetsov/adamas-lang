require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_infer_concrete_return_type_from_body(
    node : Adamas::Compiler::Frontend::DefNode,
    resolved_arena : Adamas::Compiler::Frontend::ArenaLike,
    node_expr_id : Adamas::Compiler::Frontend::ExprId? = nil,
  ) : Adamas::HIR::TypeRef?
    infer_concrete_return_type_from_body(
      node,
      preferred_arena: resolved_arena,
      node_expr_id: node_expr_id,
    )
  end

  def __test_phase0_body_infer_counts : Hash(Adamas::Compiler::Semantic::DefIdentity, Int32)
    @phase0_body_infer_counts.dup
  end
end

private def parse_phase0_metric_program(
  code : String,
) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

private def first_phase0_metric_def(
  arena : Adamas::Compiler::Frontend::ArenaLike,
  exprs : Array(Adamas::Compiler::Frontend::ExprId),
) : {Adamas::Compiler::Frontend::ExprId, Adamas::Compiler::Frontend::DefNode}
  def_expr = exprs.find do |expr_id|
    arena[expr_id].is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  raise "No function definition found" unless def_expr
  {def_expr, arena[def_expr].as(Adamas::Compiler::Frontend::DefNode)}
end

describe Adamas::HIR::AstToHir do
  describe "phase0 body inference metrics" do
    it "collapses reparsed defs by canonical identity" do
      code = <<-CRYSTAL
        def sample(value : Int32)
          value + 1
        end
      CRYSTAL

      arena_a, exprs_a = parse_phase0_metric_program(code)
      arena_b, exprs_b = parse_phase0_metric_program(code)
      expr_id_a, def_a = first_phase0_metric_def(arena_a, exprs_a)
      expr_id_b, def_b = first_phase0_metric_def(arena_b, exprs_b)

      path = "/tmp/phase0_body_infer_identity_spec.cr"
      sources_by_arena = {
        arena_a.object_id => code,
        arena_b.object_id => code,
      }
      paths_by_arena = {
        arena_a.object_id => path,
        arena_b.object_id => path,
      }

      converter = Adamas::HIR::AstToHir.new(
        arena_b,
        sources_by_arena: sources_by_arena,
        paths_by_arena: paths_by_arena,
        main_arenas: [arena_a, arena_b],
      )

      previous = ENV["ADAMAS_PHASE0_METRICS"]?
      ENV["ADAMAS_PHASE0_METRICS"] = "1"
      begin
        converter.__test_infer_concrete_return_type_from_body(def_a, arena_a, expr_id_a)
        converter.__test_infer_concrete_return_type_from_body(def_b, arena_b, expr_id_b)

        counts = converter.__test_phase0_body_infer_counts
        counts.size.should eq(1)
        identity = counts.keys.first
        identity.arena_id.should eq(arena_a.object_id.to_u64)
        counts[identity].should eq(2)
      ensure
        if previous
          ENV["ADAMAS_PHASE0_METRICS"] = previous
        else
          ENV.delete("ADAMAS_PHASE0_METRICS")
        end
      end
    end

    it "normalizes caller arenas away from the canonical def identity" do
      code = <<-CRYSTAL
        def sample(value : Int32)
          value + 1
        end
      CRYSTAL

      arena_a, exprs_a = parse_phase0_metric_program(code)
      arena_b, exprs_b = parse_phase0_metric_program(code)
      arena_c, _exprs_c = parse_phase0_metric_program(code)
      expr_id_a, def_a = first_phase0_metric_def(arena_a, exprs_a)
      expr_id_b, def_b = first_phase0_metric_def(arena_b, exprs_b)

      path = "/tmp/phase0_body_infer_identity_spec_caller_arena.cr"
      sources_by_arena = {
        arena_a.object_id => code,
        arena_b.object_id => code,
        arena_c.object_id => code,
      }
      paths_by_arena = {
        arena_a.object_id => path,
        arena_b.object_id => path,
        arena_c.object_id => path,
      }

      converter = Adamas::HIR::AstToHir.new(
        arena_c,
        sources_by_arena: sources_by_arena,
        paths_by_arena: paths_by_arena,
        main_arenas: [arena_a, arena_b, arena_c],
      )

      previous = ENV["ADAMAS_PHASE0_METRICS"]?
      ENV["ADAMAS_PHASE0_METRICS"] = "1"
      begin
        converter.__test_infer_concrete_return_type_from_body(def_a, arena_a, expr_id_a)
        converter.__test_infer_concrete_return_type_from_body(def_b, arena_c, expr_id_b)

        counts = converter.__test_phase0_body_infer_counts
        counts.size.should eq(1)
        identity = counts.keys.first
        identity.arena_id.should eq(arena_a.object_id.to_u64)
        counts[identity].should eq(2)
      ensure
        if previous
          ENV["ADAMAS_PHASE0_METRICS"] = previous
        else
          ENV.delete("ADAMAS_PHASE0_METRICS")
        end
      end
    end
  end
end
