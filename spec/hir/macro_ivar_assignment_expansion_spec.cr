require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_monomorphize_macro_ivar_owner(
    base_name : String,
    type_args : Array(String),
    specialized_name : String,
  ) : Nil
    monomorphize_generic_class(base_name, type_args, specialized_name)
  end

  def __test_macro_ivar_fields(owner_name : String)
    @class_info[owner_name].ivars
  end

  def __test_macro_ivar_type_name(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end
end

private def register_macro_ivar_assignment_fixture : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class MacroIvarAssignmentToken
    end

    class MacroIvarAssignmentOuter
    end

    class MacroIvarAssignmentStorage(T)
    end

    class MacroIvarAssignmentOwner(T)
      @direct_storage = uninitialized MacroIvarAssignmentStorage(T)

      {% if true %}
      @then_nominal = uninitialized MacroIvarAssignmentStorage(MacroIvarAssignmentToken)
      @then_generic = uninitialized MacroIvarAssignmentStorage(T)
      @constructed = MacroIvarAssignmentToken.new
      {% else %}
      @dead_then = uninitialized Bool
      {% end %}

      {% if false %}
      @dead_else = uninitialized Bool
      {% else %}
      @selected_else = uninitialized MacroIvarAssignmentStorage(T)
      {% end %}
    end
    CRYSTAL

  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  program.roots.each do |root|
    node = arena[root]
    converter.register_class(node) if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
  end
  converter.__test_monomorphize_macro_ivar_owner(
    "MacroIvarAssignmentOwner",
    ["MacroIvarAssignmentOuter"],
    "MacroIvarAssignmentOwner(MacroIvarAssignmentOuter)",
  )
  converter
end

describe "macro-expanded class ivar assignment registration" do
  it "registers fields only from selected branches and retains their exact type and default arena" do
    converter = register_macro_ivar_assignment_fixture
    owner_name = "MacroIvarAssignmentOwner(MacroIvarAssignmentOuter)"
    fields = converter.__test_macro_ivar_fields(owner_name)
    fields.map(&.name).sort.should eq([
      "@constructed",
      "@direct_storage",
      "@selected_else",
      "@then_generic",
      "@then_nominal",
    ])

    fields_by_name = fields.to_h { |field| {field.name, field} }
    converter.__test_macro_ivar_type_name(fields_by_name["@then_nominal"].type).should eq(
      "MacroIvarAssignmentStorage(MacroIvarAssignmentToken)",
    )
    converter.__test_macro_ivar_type_name(fields_by_name["@then_generic"].type).should eq(
      "MacroIvarAssignmentStorage(MacroIvarAssignmentOuter)",
    )
    converter.__test_macro_ivar_type_name(fields_by_name["@selected_else"].type).should eq(
      "MacroIvarAssignmentStorage(MacroIvarAssignmentOuter)",
    )

    constructed = fields_by_name["@constructed"]
    default_expr_id = constructed.default_expr_id.not_nil!
    default_arena = constructed.default_arena.not_nil!
    default_arena.object_id.should_not eq(converter.arena.object_id)
    default = default_arena[default_expr_id].as(Adamas::Compiler::Frontend::MemberAccessNode)
    String.new(default.member).should eq("new")
    receiver = default_arena[default.object].as(Adamas::Compiler::Frontend::IdentifierNode)
    String.new(receiver.name).should eq("MacroIvarAssignmentToken")
  end
end
