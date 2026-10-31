require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_void_generic_identity_refs(
    names : Array(String),
    namespace : String? = nil,
  ) : Array(Adamas::HIR::TypeRef)
    old_class = @current_class
    old_namespace = @current_namespace_override
    old_defer = @defer_monomorphization
    begin
      @current_namespace_override = namespace
      @current_class = namespace ? "#{namespace}::Probe" : nil
      # Register each requested spelling immediately so the test observes the
      # ClassInfo/method family chosen by that spelling, not just pending names.
      @defer_monomorphization = false
      names.map { |name| type_ref_for_name(name) }
    ensure
      @current_class = old_class
      @current_namespace_override = old_namespace
      @defer_monomorphization = old_defer
    end
  end

  def __test_void_generic_identity_families(base_name : String) : Array(String)
    @class_info.keys.select { |name| name.starts_with?("#{base_name}(") }.sort
  end

  def __test_void_generic_identity_method_owner(type : Adamas::HIR::TypeRef) : String?
    old_class = @current_class
    old_namespace = @current_namespace_override
    owner = get_type_name_from_ref(type)
    @current_class = owner
    @current_namespace_override = nil
    resolve_method_with_inheritance(owner, "typed_value")
  ensure
    @current_class = old_class
    @current_namespace_override = old_namespace
  end
end

private def void_generic_owner_identity_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class Box(T)
      def typed_value : T
      end
    end

    struct Pointer(T)
      def typed_value : T
      end
    end

    module VoidGenericIdentityScope
      class Void
      end

      class Probe
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  converter.arena = arena
  converter.seed_top_level_type_names(["Box", "Pointer", "VoidGenericIdentityScope"])
  converter.seed_top_level_class_kinds([
    {"Box", false}, {"Pointer", true},
  ])
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end
  converter
end

describe "resolved Void generic owner identity" do
  {
    {"Pointer", ["::Pointer(::Void)", "Pointer(Void)"] of String, "Pointer(Void)"},
    {"Box", ["::Box(::Void)", "Box(Void)"] of String, "Box(Void)"},
  }.each do |base_name, spellings, expected_owner|
    it "coalesces #{base_name}(Void) source spellings in either request order" do
      [spellings, spellings.reverse].each do |order|
        converter = void_generic_owner_identity_converter
        refs = converter.__test_void_generic_identity_refs(order)
        first, second = refs

        first.should_not eq(Adamas::HIR::TypeRef::VOID)
        first.should eq(second)
        converter.module.get_type_descriptor(first).not_nil!.name.should eq(expected_owner)
        converter.module.get_type_descriptor(second).not_nil!.name.should eq(expected_owner)

        converter.__test_void_generic_identity_families(base_name).should eq([expected_owner])
        converter.__test_void_generic_identity_method_owner(first).should eq("#{expected_owner}#typed_value")
        converter.__test_void_generic_identity_method_owner(second).should eq("#{expected_owner}#typed_value")
      end
    end
  end

  it "does not materialize an unresolved generic parameter as Void" do
    converter = void_generic_owner_identity_converter

    converter.__test_void_generic_identity_refs(["Box(T)"]).should eq([Adamas::HIR::TypeRef::VOID])
    converter.__test_void_generic_identity_families("Box").should be_empty
  end

  it "keeps a root-anchored Void distinct from a shadowing nested Void in either order" do
    orders = [
      ["Box(Void)", "::Box(::Void)"],
      ["::Box(::Void)", "Box(Void)"],
    ]

    orders.each do |order|
      converter = void_generic_owner_identity_converter
      refs = converter.__test_void_generic_identity_refs(order, "VoidGenericIdentityScope")
      local_index = order.index("Box(Void)").not_nil!
      root_index = order.index("::Box(::Void)").not_nil!
      local_type = refs[local_index]
      root_type = refs[root_index]

      local_type.should_not eq(root_type)
      converter.module.get_type_descriptor(local_type).not_nil!.name.should eq(
        "Box(VoidGenericIdentityScope::Void)",
      )
      converter.module.get_type_descriptor(root_type).not_nil!.name.should eq("Box(Void)")
      converter.__test_void_generic_identity_families("Box").should eq([
        "Box(Void)", "Box(VoidGenericIdentityScope::Void)",
      ])
      converter.__test_void_generic_identity_method_owner(local_type).should eq(
        "Box(VoidGenericIdentityScope::Void)#typed_value",
      )
      converter.__test_void_generic_identity_method_owner(root_type).should eq("Box(Void)#typed_value")
    end
  end
end
