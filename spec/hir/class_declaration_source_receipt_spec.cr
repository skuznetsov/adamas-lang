require "../spec_helper"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_class_declaration_source(
    expr_id : Adamas::Compiler::Frontend::ExprId,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : ClassDeclarationSource
    ClassDeclarationSource.new(expr_id, arena)
  end

  def __test_register_class_declaration_source(
    node : Adamas::Compiler::Frontend::ClassNode,
    name : String,
    source : ClassDeclarationSource,
  ) : Nil
    register_class_with_name(node, name, source)
  end

  def __test_lower_class_with_ambient_arena(
    node : Adamas::Compiler::Frontend::ClassNode,
    name : String,
    ambient : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    original = @arena
    with_arena(ambient) do
      lower_class_with_name(node, name)
    end
    @arena.same?(original)
  end

  def __test_class_registration_snapshot(name : String) : NamedTuple(class_registered: Bool, constants: Array(String))
    constants = @constant_defs.select { |constant| constant.starts_with?(name + "::") }.sort
    {class_registered: @class_info.has_key?(name), constants: constants}
  end

  def __test_class_method_source_matches?(
    node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Bool
    @function_defs.any? do |name, definition|
      definition.same?(node) && @function_def_arenas[name]?.try(&.same?(arena)) == true
    end
  end

  def __test_retained_class_source_roots_node?(
    node : Adamas::Compiler::Frontend::ClassNode,
  ) : Bool
    retained = @class_declaration_sources_by_node[node.object_id.to_u64]?
    retained ? retained.any?(&.node.same?(node)) : false
  end
end

private def parse_class_declaration_receipt_source(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  raise "parser diagnostics: #{parser.diagnostics.size}" unless parser.diagnostics.empty?
  program
end

private def first_class_declaration(program)
  arena = program.arena
  expr_id = program.roots.find { |id| arena[id].is_a?(Adamas::Compiler::Frontend::ClassNode) }
  raise "class declaration not found" unless expr_id
  node = arena[expr_id.not_nil!].as(Adamas::Compiler::Frontend::ClassNode)
  {expr_id: expr_id.not_nil!, node: node}
end

private def first_class_method(node : Adamas::Compiler::Frontend::ClassNode, arena : Adamas::Compiler::Frontend::ArenaLike)
  body = node.body || raise "class body not found"
  definition = body.compact_map do |member_id|
    member = arena[member_id]
    if member.is_a?(Adamas::Compiler::Frontend::VisibilityModifierNode)
      inner_id = member.expression
      member = arena[inner_id]
    end
    member.as?(Adamas::Compiler::Frontend::DefNode)
  end.first?
  definition || raise "class method not found"
end

describe "class declaration source receipts" do
  it "rejects a same-shape foreign source before class or constant publication" do
    source = <<-CRYSTAL
      class ReceiptCollision
        VALUE = 65
      end
    CRYSTAL
    target_program = parse_class_declaration_receipt_source(source)
    foreign_program = parse_class_declaration_receipt_source(source)
    target = first_class_declaration(target_program)
    foreign = first_class_declaration(foreign_program)
    target_arena = target_program.arena
    foreign_arena = foreign_program.arena
    target[:node].same?(foreign[:node]).should be_false

    converter = Adamas::HIR::AstToHir.new(target_arena)
    converter.no_prelude = true
    before = converter.__test_class_registration_snapshot("ReceiptCollision")

    expect_raises(Adamas::HIR::LoweringError) do
      converter.__test_register_class_declaration_source(
        target[:node],
        "ReceiptCollision",
        converter.__test_class_declaration_source(foreign[:expr_id], foreign_arena),
      )
    end

    converter.__test_class_registration_snapshot("ReceiptCollision").should eq(before)
  end

  it "executes a nonzero-offset VirtualArena class in its exact file arena across valid views" do
    source = <<-CRYSTAL
      class VirtualReceiptOwner
        def self.value : Int32
          65
        end
      end
    CRYSTAL
    decoy_source = <<-CRYSTAL
      class AmbientReceiptDecoy
        def self.value : Int32
          66
        end
      end
    CRYSTAL
    program = parse_class_declaration_receipt_source(source)
    decoy_program = parse_class_declaration_receipt_source(decoy_source)
    file_arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
    decoy_arena = decoy_program.arena
    declaration = first_class_declaration(program)
    definition = first_class_method(declaration[:node], file_arena)

    prefix_arena = Adamas::Compiler::Frontend::AstArena.new
    prefix_arena.add(Adamas::Compiler::Frontend::NilNode.new(Adamas::Compiler::Frontend::Span.zero))
    virtual = Adamas::Compiler::Frontend::VirtualArena.new
    virtual.add_file_arena("empty.cr", Adamas::Compiler::Frontend::AstArena.new)
    virtual.add_file_arena("prefix.cr", prefix_arena)
    virtual.add_file_arena("owner.cr", file_arena)
    virtual_id = Adamas::Compiler::Frontend::ExprId.new(prefix_arena.size + declaration[:expr_id].index)
    virtual[virtual_id].same?(declaration[:node]).should be_true

    converter = Adamas::HIR::AstToHir.new(
      virtual,
      sources_by_arena: {
        virtual.object_id.to_u64    => source,
        file_arena.object_id.to_u64 => source,
        decoy_arena.object_id.to_u64 => decoy_source,
      },
      main_arenas: [file_arena, decoy_arena] of Adamas::Compiler::Frontend::ArenaLike,
    )
    converter.no_prelude = true
    virtual_source = converter.__test_class_declaration_source(virtual_id, virtual)
    file_source = converter.__test_class_declaration_source(declaration[:expr_id], file_arena)
    converter.__test_register_class_declaration_source(declaration[:node], "VirtualReceiptOwner", virtual_source)
    # Retain both exact views; they execute from the same canonical file arena.
    converter.__test_register_class_declaration_source(declaration[:node], "VirtualReceiptOwner", file_source)

    converter.__test_lower_class_with_ambient_arena(
      declaration[:node],
      "VirtualReceiptOwner",
      decoy_arena,
    ).should be_true
    converter.__test_class_method_source_matches?(definition, file_arena).should be_true
  end

  it "rejects a retained VirtualArena receipt after its backing file is replaced" do
    source = <<-CRYSTAL
      class ReplacedReceiptOwner
        def self.value : Int32
          65
        end
      end
    CRYSTAL
    original_program = parse_class_declaration_receipt_source(source)
    replacement_program = parse_class_declaration_receipt_source(source)
    original = first_class_declaration(original_program)
    original_arena = original_program.arena.as(Adamas::Compiler::Frontend::AstArena)
    prefix_arena = Adamas::Compiler::Frontend::AstArena.new
    prefix_arena.add(Adamas::Compiler::Frontend::NilNode.new(Adamas::Compiler::Frontend::Span.zero))
    virtual = Adamas::Compiler::Frontend::VirtualArena.new
    virtual.add_file_arena("prefix.cr", prefix_arena)
    virtual.add_file_arena("owner.cr", original_arena)
    virtual_id = Adamas::Compiler::Frontend::ExprId.new(prefix_arena.size + original[:expr_id].index)
    converter = Adamas::HIR::AstToHir.new(
      virtual,
      sources_by_arena: {virtual.object_id.to_u64 => source, original_arena.object_id.to_u64 => source},
    )
    converter.no_prelude = true
    converter.__test_register_class_declaration_source(
      original[:node],
      "ReplacedReceiptOwner",
      converter.__test_class_declaration_source(virtual_id, virtual),
    )
    converter.__test_retained_class_source_roots_node?(original[:node]).should be_true
    before = converter.__test_class_registration_snapshot("ReplacedReceiptOwner")

    virtual.replace_file_arena("owner.cr", replacement_program.arena.as(Adamas::Compiler::Frontend::AstArena))
    virtual[virtual_id].same?(original[:node]).should be_false
    expect_raises(Adamas::HIR::LoweringError) do
      converter.__test_lower_class_with_ambient_arena(
        original[:node],
        "ReplacedReceiptOwner",
        virtual,
      )
    end

    converter.__test_class_registration_snapshot("ReplacedReceiptOwner").should eq(before)
  end
end
