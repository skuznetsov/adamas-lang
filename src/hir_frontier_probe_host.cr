require "./compiler/bootstrap_shims"
require "./compiler/frontend/parser"
require "./compiler/hir/ast_to_hir"

module HIRFrontierProbeHost
  alias ArenaLike = CrystalV2::Compiler::Frontend::ArenaLike
  alias ExprId = CrystalV2::Compiler::Frontend::ExprId
  alias FrontendNode = CrystalV2::Compiler::Frontend::Node

  record ParsedUnit,
    arena : ArenaLike,
    roots : Array(ExprId),
    path : String,
    source : String

  def self.unwrap_visibility(
    arena : ArenaLike,
    node : FrontendNode,
  ) : FrontendNode
    current = node
    while current.is_a?(CrystalV2::Compiler::Frontend::VisibilityModifierNode)
      current = arena[current.expression]
    end
    current
  end

  def self.require_path_from_node(
    arena : ArenaLike,
    node : CrystalV2::Compiler::Frontend::RequireNode,
  ) : String?
    path_node = arena[node.path]
    return nil unless path_node.is_a?(CrystalV2::Compiler::Frontend::StringNode)
    String.new(path_node.value)
  end

  def self.resolve_require(current_path : String, required_path : String) : String?
    candidate = File.expand_path(required_path, File.dirname(current_path))
    return candidate if File.file?(candidate)

    with_ext = candidate.ends_with?(".cr") ? candidate : "#{candidate}.cr"
    return with_ext if File.file?(with_ext)

    nil
  end

  def self.parse_file_recursive(
    path : String,
    loaded : Set(String),
    units : Array(ParsedUnit),
  ) : Nil
    abs_path = File.expand_path(path)
    return if loaded.includes?(abs_path)
    loaded.add(abs_path)

    source = File.read(abs_path)
    lexer = CrystalV2::Compiler::Frontend::Lexer.new(source)
    parser = CrystalV2::Compiler::Frontend::Parser.new(lexer)
    roots = parser.parse_program_roots
    arena = parser.arena
    units << ParsedUnit.new(arena, roots, abs_path, source)

    roots.each do |expr_id|
      next if expr_id.invalid?
      node = unwrap_visibility(arena, arena[expr_id])
      next unless node.is_a?(CrystalV2::Compiler::Frontend::RequireNode)
      next unless required_path = require_path_from_node(arena, node)
      next unless resolved_path = resolve_require(abs_path, required_path)
      parse_file_recursive(resolved_path, loaded, units)
    end
  end

  def self.collect_top_level_names(
    arena : ArenaLike,
    roots : Array(ExprId),
    type_names : Set(String),
    class_kinds : Array({String, Bool}),
  ) : Nil
    roots.each do |expr_id|
      next if expr_id.invalid?
      node = unwrap_visibility(arena, arena[expr_id])
      case node
      when CrystalV2::Compiler::Frontend::ClassNode
        name = String.new(node.name)
        type_names.add(name)
        class_kinds << {name, node.is_struct == true}
      when CrystalV2::Compiler::Frontend::ModuleNode
        type_names.add(String.new(node.name))
      when CrystalV2::Compiler::Frontend::EnumNode
        type_names.add(String.new(node.name))
      when CrystalV2::Compiler::Frontend::AliasNode
        type_names.add(String.new(node.name))
      end
    end
  end

  def self.run(root_path : String) : Nil
    units = [] of ParsedUnit
    parse_file_recursive(root_path, Set(String).new, units)
    raise "no parsed units" if units.empty?

    sources_by_arena = {} of UInt64 => String
    paths_by_arena = {} of UInt64 => String
    main_arenas = [] of ArenaLike
    type_names = Set(String).new
    class_kinds = [] of {String, Bool}

    units.each do |unit|
      arena_id = unit.arena.object_id.to_u64
      sources_by_arena[arena_id] = unit.source
      paths_by_arena[arena_id] = unit.path
      main_arenas << unit.arena
      collect_top_level_names(unit.arena, unit.roots, type_names, class_kinds)
    end

    hir_module = Crystal::HIR::Module.new("probe")
    converter = Crystal::HIR::AstToHir.new(
      units.first.arena,
      "probe",
      sources_by_arena,
      paths_by_arena,
      main_arenas,
      hir_module,
      [] of String,
    )
    converter.seed_top_level_type_names(type_names)
    converter.seed_top_level_class_kinds(class_kinds)

    units.each do |unit|
      converter.arena = unit.arena
      unit.roots.each do |expr_id|
        next if expr_id.invalid?
        node = unwrap_visibility(unit.arena, unit.arena[expr_id])
        case node
        when CrystalV2::Compiler::Frontend::ModuleNode
          converter.register_module(node)
        when CrystalV2::Compiler::Frontend::ClassNode
          converter.register_class(node)
        when CrystalV2::Compiler::Frontend::EnumNode
          converter.register_enum(node)
        when CrystalV2::Compiler::Frontend::AliasNode
          converter.register_alias(node)
        when CrystalV2::Compiler::Frontend::MacroDefNode
          converter.register_macro(node)
        end
      end
    end

    puts "OK units=#{units.size}"
  end
end

abort "usage: hir_frontier_probe_host <source.cr>" if ARGV.empty?
HIRFrontierProbeHost.run(ARGV[0])
