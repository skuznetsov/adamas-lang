require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_publish_direct_accessor(
    owner : String,
    method_name : String,
    registered_name : String,
    source_def : Adamas::Compiler::Frontend::DefNode,
    source_arena : Adamas::Compiler::Frontend::ArenaLike,
    source_order : Array(Int32),
    update_registry : Bool = true,
    registered_arena : Adamas::Compiler::Frontend::ArenaLike? = nil,
  ) : Nil
    @source_accessor_order_owner = owner
    @source_declaration_node_order[{source_arena, source_def.object_id.to_u64}] = source_order
    if update_registry
      set_function_def_entry(registered_name, source_def, record_current_arena: false)
      set_function_def_arena(registered_name, registered_arena || source_arena)
    end
    record_direct_instance_def_name(owner, method_name, source_def, source_arena, registered_name)
  end

  def __test_register_source_accessor_macro(node : Adamas::Compiler::Frontend::MacroDefNode) : Nil
    register_macro(node)
  end

  def __test_register_source_accessor_class(
    node : Adamas::Compiler::Frontend::ClassNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    self.arena = arena
    register_class(node)
  end

  def __test_mark_accessor_order_seen(
    owner : String,
    node : Adamas::Compiler::Frontend::ClassNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    begin_source_accessor_order_recording(owner, node, arena)
  end

  def __test_direct_accessor_origin(
    owner : String,
    method_name : String,
  ) : Tuple(Adamas::Compiler::Frontend::DefNode, Adamas::Compiler::Frontend::ArenaLike)?
    direct_accessor_def_origin(owner, method_name)
  end

  def __test_registered_source_def(name : String) : Adamas::Compiler::Frontend::DefNode?
    @function_defs[name]?
  end

  def __test_registered_source_arena(name : String) : Adamas::Compiler::Frontend::ArenaLike?
    @function_def_arenas[name]?
  end
end

private def parse_direct_accessor_defs
  source = <<-CRYSTAL
    class DirectAccessorReceiptOwner
      def value
        1
      end

      def value
        2
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  class_node = arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
  defs = [] of Adamas::Compiler::Frontend::DefNode
  class_node.body.not_nil!.each do |id|
    node = arena[id]
    defs << node if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  defs.size.should eq(2)
  {arena, defs}
end

private def parse_direct_accessor_class(value : Int32)
  source = <<-CRYSTAL
    class DirectAccessorReceiptOwner
      def value
        #{value}
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  class_node = arena[program.roots.first].as(Adamas::Compiler::Frontend::ClassNode)
  def_node = arena[class_node.body.not_nil!.first].as(Adamas::Compiler::Frontend::DefNode)
  {arena, class_node, def_node}
end

private def parse_direct_accessor_macro_class(macro_first : Bool)
  macro_call = "add_source_value()"
  explicit_def = <<-CRYSTAL
    def value : Int32
      66
    end
  CRYSTAL
  members = if macro_first
              "#{macro_call}\n#{explicit_def}"
            else
              "#{explicit_def}\n#{macro_call}"
            end
  source = <<-CRYSTAL
    macro add_source_value
      def value : Int32
        65
      end
    end

    class ReplayedMacroAccessorOwner
      #{members}
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  macro_node = nil.as(Adamas::Compiler::Frontend::MacroDefNode?)
  class_node = nil.as(Adamas::Compiler::Frontend::ClassNode?)
  explicit_def = nil.as(Adamas::Compiler::Frontend::DefNode?)
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::MacroDefNode
      macro_node = node
    when Adamas::Compiler::Frontend::ClassNode
      class_node = node
    end
  end
  class_node.not_nil!.body.not_nil!.each do |member_id|
    node = arena[member_id]
    explicit_def = node if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  {arena, macro_node.not_nil!, class_node.not_nil!, explicit_def.not_nil!}
end

describe "direct accessor origin publication" do
  it "refreshes an equal-order origin only for the exact newly registered Def/Arena pair" do
    arena, defs = parse_direct_accessor_defs
    converter = Adamas::HIR::AstToHir.new(arena)
    owner = "DirectAccessorReceiptOwner"
    key = "DirectAccessorReceiptOwner#value"
    first, reparsed = defs

    converter.__test_publish_direct_accessor(owner, "value", key, first, arena, [7])
    converter.__test_direct_accessor_origin(owner, "value").not_nil![0].should be(first)

    converter.__test_publish_direct_accessor(owner, "value", key, reparsed, arena, [7])

    converter.__test_registered_source_def(key).should be(reparsed)
    origin = converter.__test_direct_accessor_origin(owner, "value").not_nil!
    origin[0].should be(reparsed)
    origin[1].should be(arena)
  end

  it "does not let an older declaration replay replace the later registered winner" do
    arena, defs = parse_direct_accessor_defs
    converter = Adamas::HIR::AstToHir.new(arena)
    owner = "DirectAccessorReceiptOwner"
    key = "DirectAccessorReceiptOwner#value"
    earlier, later = defs

    converter.__test_publish_direct_accessor(owner, "value", key, earlier, arena, [1])
    converter.__test_publish_direct_accessor(owner, "value", key, later, arena, [2])
    converter.__test_publish_direct_accessor(
      owner, "value", key, earlier, arena, [1], update_registry: false,
    )

    converter.__test_registered_source_def(key).should be(later)
    converter.__test_direct_accessor_origin(owner, "value").not_nil![0].should be(later)
  end

  it "does not refresh an origin when the registered Def is paired with a foreign arena" do
    arena, defs = parse_direct_accessor_defs
    foreign_arena, foreign_defs = parse_direct_accessor_defs
    converter = Adamas::HIR::AstToHir.new(arena)
    owner = "DirectAccessorReceiptOwner"
    key = "DirectAccessorReceiptOwner#value"
    prior = defs.first
    current = foreign_defs.last

    converter.__test_publish_direct_accessor(owner, "value", key, prior, arena, [4])
    converter.__test_publish_direct_accessor(
      owner,
      "value",
      key,
      current,
      foreign_arena,
      [8],
      registered_arena: arena,
    )

    converter.__test_registered_source_def(key).should be(current)
    origin = converter.__test_direct_accessor_origin(owner, "value").not_nil!
    origin[0].should be(prior)
    origin[1].should be(arena)
  end

  it "keeps a later ordinary Def current after replaying an earlier macro declaration" do
    arena, macro_node, class_node, explicit_def = parse_direct_accessor_macro_class(true)
    converter = Adamas::HIR::AstToHir.new(arena)
    converter.no_prelude = true
    registry_owner = "ReplayedMacroAccessorOwner"
    key = "#{registry_owner}#value"

    converter.__test_register_source_accessor_macro(macro_node)
    converter.record_source_declaration_order(class_node, arena)
    converter.__test_register_source_accessor_class(class_node, arena)
    converter.__test_registered_source_def(key).should be(explicit_def)
    converter.__test_direct_accessor_origin(registry_owner, "value").not_nil![0].should be(explicit_def)

    # The same class AST is registered again, so production's declaration-order
    # recorder sees this as a replay. Macro expansion produces a fresh Def and
    # arena, then the later ordinary Def must remain the source-order winner.
    converter.__test_mark_accessor_order_seen(registry_owner, class_node, arena).should be_false
    converter.__test_register_source_accessor_class(class_node, arena)

    registered = converter.__test_registered_source_def(key).not_nil!
    registered_arena = converter.__test_registered_source_arena(key).not_nil!
    registered.should be(explicit_def)
    origin = converter.__test_direct_accessor_origin(registry_owner, "value").not_nil!
    origin[0].should be(registered)
    origin[1].should be(registered_arena)
  end

  it "keeps a later macro declaration current after replaying an earlier ordinary Def" do
    arena, macro_node, class_node, explicit_def = parse_direct_accessor_macro_class(false)
    converter = Adamas::HIR::AstToHir.new(arena)
    converter.no_prelude = true
    registry_owner = "ReplayedMacroAccessorOwner"
    key = "#{registry_owner}#value"

    converter.__test_register_source_accessor_macro(macro_node)
    converter.record_source_declaration_order(class_node, arena)
    converter.__test_register_source_accessor_class(class_node, arena)
    first = converter.__test_registered_source_def(key).not_nil!
    first.should_not be(explicit_def)
    converter.__test_direct_accessor_origin(registry_owner, "value").not_nil![0].should be(first)
    converter.__test_mark_accessor_order_seen(registry_owner, class_node, arena).should be_false
    converter.__test_register_source_accessor_class(class_node, arena)

    registered = converter.__test_registered_source_def(key).not_nil!
    registered_arena = converter.__test_registered_source_arena(key).not_nil!
    registered.should_not be(explicit_def)
    origin = converter.__test_direct_accessor_origin(registry_owner, "value").not_nil!
    origin[0].should be(registered)
    origin[1].should be(registered_arena)
  end
end
