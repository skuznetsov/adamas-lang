require "../frontend/ast"
require "../frontend/lexer"
require "../frontend/parser"
require "../frontend/dispatch"

module CrystalV2
  module Compiler
    module Semantic
      class CompileShadowAggregate
        record GeneratedNodeInfo,
          root_id : Frontend::ExprId,
          source : String?,
          origin_node_id : Frontend::ExprId?,
          macro_definition_node_id : Frontend::ExprId?

        record UnitSummary,
          unit_index : Int32,
          path : String,
          source : String,
          roots : Array(Frontend::ExprId),
          node_count : Int32

        getter program : Frontend::Program
        getter unit_summaries : Array(UnitSummary)

        def self.build(units : Array(NamedTuple(path: String, source: String))) : self
          aggregate_arena = Frontend::AstArena.new
          merged_roots = [] of Frontend::ExprId
          unit_summaries = [] of UnitSummary
          unit_index_by_node = [] of Int32

          units.each_with_index do |unit, unit_index|
            lexer = Frontend::Lexer.new(unit[:source])
            parser = Frontend::Parser.new(lexer, aggregate_arena)
            roots = parser.parse_program_roots
            merged_roots.concat(roots)
            grow_index_owner_map(unit_index_by_node, aggregate_arena.size)
            node_count = assign_unit_nodes(aggregate_arena, roots, unit_index.to_i32, unit_index_by_node)
            unit_summaries << UnitSummary.new(
              unit_index: unit_index.to_i32,
              path: unit[:path],
              source: unit[:source],
              roots: roots,
              node_count: node_count,
            )
          end

          new(
            Frontend::Program.new(aggregate_arena, merged_roots),
            unit_summaries,
            unit_index_by_node,
          )
        end

        def initialize(
          @program : Frontend::Program,
          @unit_summaries : Array(UnitSummary),
          @unit_index_by_node : Array(Int32),
        )
          @unit_index_by_path = {} of String => Int32
          @unit_summaries.each do |unit_summary|
            @unit_index_by_path[unit_summary.path] = unit_summary.unit_index
          end
          @generated_node_count_by_unit = Array(Int32).new(@unit_summaries.size, 0)
          @generated_root_sources = {} of Int32 => String
          @generated_root_by_node = {} of Int32 => Int32
          @generated_root_origins = {} of Int32 => Frontend::ExprId
          @generated_root_macro_defs = {} of Int32 => Frontend::ExprId
        end

        def unit_index_for(expr_id : Frontend::ExprId) : Int32?
          return nil if expr_id.invalid?
          index = expr_id.index
          return nil if index < 0 || index >= @unit_index_by_node.size
          unit_index = @unit_index_by_node.unsafe_fetch(index)
          unit_index < 0 ? nil : unit_index
        end

        def unit_for(expr_id : Frontend::ExprId) : UnitSummary?
          if unit_index = unit_index_for(expr_id)
            @unit_summaries.unsafe_fetch(unit_index)
          else
            nil
          end
        end

        def path_for(expr_id : Frontend::ExprId) : String?
          unit_for(expr_id).try(&.path)
        end

        def attach_generated_node_paths(generated_node_file_paths : Hash(Int32, String)) : Nil
          generated_node_file_paths.each do |node_index, file_path|
            next unless unit_index = @unit_index_by_path[file_path]?
            while @unit_index_by_node.size < node_index + 1
              @unit_index_by_node << -1
            end

            current = @unit_index_by_node.unsafe_fetch(node_index)
            next if current == unit_index

            if current >= 0
              if current < @generated_node_count_by_unit.size && @generated_node_count_by_unit[current] > 0
                @generated_node_count_by_unit[current] -= 1
              end
            end

            @unit_index_by_node[node_index] = unit_index
            @generated_node_count_by_unit[unit_index] += 1
          end
        end

        def attach_generated_overlay(
          generated_node_file_paths : Hash(Int32, String),
          generated_root_sources : Hash(Int32, String),
          generated_root_by_node : Hash(Int32, Int32),
          generated_root_origins : Hash(Int32, Frontend::ExprId),
          generated_root_macro_defs : Hash(Int32, Frontend::ExprId)
        ) : Nil
          attach_generated_node_paths(generated_node_file_paths)
          @generated_root_sources = generated_root_sources.dup
          @generated_root_by_node = generated_root_by_node.dup
          @generated_root_origins = generated_root_origins.dup
          @generated_root_macro_defs = generated_root_macro_defs.dup
        end

        def generated_info_for(expr_id : Frontend::ExprId) : GeneratedNodeInfo?
          return nil if expr_id.invalid?
          node_index = expr_id.index

          root_index = if @generated_root_sources.has_key?(node_index) ||
                          @generated_root_origins.has_key?(node_index) ||
                          @generated_root_macro_defs.has_key?(node_index)
                         node_index
                       else
                         @generated_root_by_node[node_index]?
                       end
          return nil unless root_index

          GeneratedNodeInfo.new(
            Frontend::ExprId.new(root_index),
            @generated_root_sources[root_index]?,
            @generated_root_origins[root_index]?,
            @generated_root_macro_defs[root_index]?,
          )
        end

        def generated_source_for(expr_id : Frontend::ExprId) : String?
          generated_info_for(expr_id).try(&.source)
        end

        def generated_origin_for(expr_id : Frontend::ExprId) : Frontend::ExprId?
          generated_info_for(expr_id).try(&.origin_node_id)
        end

        def generated_node?(expr_id : Frontend::ExprId) : Bool
          !generated_info_for(expr_id).nil?
        end

        def generated_macro_definition_for(expr_id : Frontend::ExprId) : Frontend::ExprId?
          generated_info_for(expr_id).try(&.macro_definition_node_id)
        end

        def generated_node_count_for_unit(unit_index : Int32) : Int32
          return 0 if unit_index < 0 || unit_index >= @generated_node_count_by_unit.size
          @generated_node_count_by_unit.unsafe_fetch(unit_index)
        end

        def owned_node_count_for_unit(unit_index : Int32) : Int32
          return 0 if unit_index < 0 || unit_index >= @unit_summaries.size
          unit_summary = @unit_summaries.unsafe_fetch(unit_index)
          unit_summary.node_count + generated_node_count_for_unit(unit_index)
        end

        private def self.grow_index_owner_map(unit_index_by_node : Array(Int32), arena_size : Int32) : Nil
          while unit_index_by_node.size < arena_size
            unit_index_by_node << -1
          end
        end

        private def self.assign_unit_nodes(
          arena : Frontend::AstArena,
          roots : Array(Frontend::ExprId),
          unit_index : Int32,
          unit_index_by_node : Array(Int32)
        ) : Int32
          stack = [] of Frontend::ExprId
          roots.each { |root| stack << root unless root.invalid? }
          assigned = 0

          until stack.empty?
            expr_id = stack.pop
            next if expr_id.invalid?
            index = expr_id.index
            next if index < 0 || index >= unit_index_by_node.size
            next if unit_index_by_node.unsafe_fetch(index) == unit_index

            if unit_index_by_node.unsafe_fetch(index) < 0
              unit_index_by_node[index] = unit_index
              assigned += 1
            end

            Frontend::NodeDispatch.each_child_expr(arena, expr_id) do |child|
              stack << child unless child.invalid?
            end
          end

          assigned
        end
      end
    end
  end
end
