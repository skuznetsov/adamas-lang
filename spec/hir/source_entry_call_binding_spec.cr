require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  # This seam tests the admission boundary, not general named/rest inference.
  # Use a registered Def/Arena and the parsed source call when one exists.
  def __test_source_entry_binding_admitted?(
    base : String,
    actual_names : Array(String)?,
    has_named : Bool = false,
    call : Adamas::Compiler::Frontend::CallNode? = nil,
    arena : Adamas::Compiler::Frontend::ArenaLike? = nil,
    has_splat : Bool = false,
    raw_count : Int32? = nil,
  ) : Bool
    name = @function_defs.keys.find { |key| key == base || key.starts_with?("#{base}$") } || return false
    definition = @function_defs[name]
    actuals = actual_names.try &.map { |type| type_ref_for_name(type) }
    input = CallResolutionInput.new(base, actuals.try(&.size) || 0, actuals,
      true, has_splat, has_named, nil, raw_count)
    !source_entry_positional_call_binding(name, definition, actuals,
      has_named, call, arena, input).nil?
  end
end

private def parse_source_entry_binding(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?
  converter = Adamas::HIR::AstToHir.new(program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source})
  program.roots.each do |root|
    if node = program.arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end
  {converter, program}
end

describe "source entry input binding admission" do
  it "admits complete ordinary positional inputs" do
    converter, program = parse_source_entry_binding(<<-CRYSTAL)
      class EntryCallOwner
        def project(seed, other, &)
          original = seed
          yield original
        end
      end
      owner.project(seed, other) { |value| value }
    CRYSTAL
    call = program.arena[program.roots.last].as(Adamas::Compiler::Frontend::CallNode)
    converter.__test_source_entry_binding_admitted?("EntryCallOwner#project",
      ["Pointer(Void)", "Bool"], call: call, arena: program.arena).should be_true
  end

  it "withholds a raw reordered named vector even when the legacy flag is false" do
    converter, program = parse_source_entry_binding(<<-CRYSTAL)
      class EntryNamedOwner
        def project(seed, other, &)
          original = seed
          yield original
        end
      end
      owner.project(other: flag, seed: pointer) { |value| value }
    CRYSTAL
    call = program.arena[program.roots.last].as(Adamas::Compiler::Frontend::CallNode)
    converter.__test_source_entry_binding_admitted?("EntryNamedOwner#project",
      ["Bool", "Pointer(Void)"], call: call, arena: program.arena).should be_false
    converter.__test_source_entry_binding_admitted?("EntryNamedOwner#project",
      ["Bool", "Pointer(Void)"], has_named: true).should be_false
  end

  it "withholds an omitted default and admits a fully supplied default slot" do
    converter, program = parse_source_entry_binding(<<-CRYSTAL)
      class EntryDefaultOwner
        def project(seed, other = false, &)
          original = seed
          yield original
        end
      end
      owner.project(seed) { |value| value }
      owner.project(seed, other) { |value| value }
    CRYSTAL
    call = program.arena[program.roots.last].as(Adamas::Compiler::Frontend::CallNode)
    omitted_call = program.arena[program.roots[-2]].as(Adamas::Compiler::Frontend::CallNode)
    converter.__test_source_entry_binding_admitted?("EntryDefaultOwner#project",
      ["Pointer(Void)"], call: omitted_call, arena: program.arena).should be_false
    converter.__test_source_entry_binding_admitted?("EntryDefaultOwner#project",
      ["Pointer(Void)", "Bool"], call: call, arena: program.arena).should be_true
  end

  it "withholds call-site splat expansion even with a full flattened vector" do
    converter, program = parse_source_entry_binding(<<-CRYSTAL)
      class EntryExpandedOwner
        def project(seed, other, &)
          yield seed
        end
      end
      owner.project(*values) { |value| value }
    CRYSTAL
    call = program.arena[program.roots.last].as(Adamas::Compiler::Frontend::CallNode)
    converter.__test_source_entry_binding_admitted?("EntryExpandedOwner#project",
      ["Pointer(Void)", "Bool"], call: call, arena: program.arena).should be_false
    converter.__test_source_entry_binding_admitted?("EntryExpandedOwner#project",
      ["Pointer(Void)", "Bool"], has_splat: true).should be_false
  end

  it "withholds rest formals and named-only separators" do
    converter, program = parse_source_entry_binding(<<-CRYSTAL)
      class EntryRestOwner
        def project(*seed, &)
          yield seed
        end
      end
      class EntryKeywordOwner
        def project(seed, *, other, &)
          yield seed
        end
      end
      owner.project(seed) { |value| value }
      owner.project(seed, other) { |value| value }
    CRYSTAL
    rest_call = program.arena[program.roots[-2]].as(Adamas::Compiler::Frontend::CallNode)
    keyword_call = program.arena[program.roots.last].as(Adamas::Compiler::Frontend::CallNode)
    converter.__test_source_entry_binding_admitted?("EntryRestOwner#project",
      ["Pointer(Void)"], call: rest_call, arena: program.arena).should be_false
    converter.__test_source_entry_binding_admitted?("EntryKeywordOwner#project",
      ["Pointer(Void)", "Bool"], call: keyword_call, arena: program.arena).should be_false
  end

  it "withholds mangled-only, unknown, and changed raw source shapes" do
    converter, program = parse_source_entry_binding(<<-CRYSTAL)
      class EntryUnknownOwner
        def project(seed, &)
          yield seed
        end
      end
      owner.project(seed) { |value| value }
    CRYSTAL
    call = program.arena[program.roots.last].as(Adamas::Compiler::Frontend::CallNode)
    converter.__test_source_entry_binding_admitted?("EntryUnknownOwner#project",
      ["Pointer(Void)"]).should be_false
    converter.__test_source_entry_binding_admitted?("EntryUnknownOwner#project", nil).should be_false
    converter.__test_source_entry_binding_admitted?("EntryUnknownOwner#project", ["Void"]).should be_false
    converter.__test_source_entry_binding_admitted?("EntryUnknownOwner#project",
      ["Pointer(Void)"], call: call, arena: program.arena, raw_count: 0).should be_false
  end
end
