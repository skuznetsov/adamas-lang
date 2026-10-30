require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_generic_identity_type_ref(name : String, namespace : String? = nil) : Adamas::HIR::TypeRef
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_namespace_override = namespace
    if namespace
      @current_class = "#{namespace}::Probe"
    else
      @current_class = nil
    end
    type_ref_for_name(name)
  ensure
    @current_class = old_class
    @current_namespace_override = old_namespace
  end

  def __test_generic_identity_box_family : Array(String)
    @class_info.keys.select { |name| name.starts_with?("GenericIdentityBox(") }.sort
  end

  def __test_generic_identity_hash(key : Adamas::HIR::TypeRef, value : Adamas::HIR::TypeRef) : Adamas::HIR::TypeRef
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = "GenericIdentityScope::Probe"
    @current_namespace_override = "GenericIdentityScope"
    hash_type_for_entry_types(key, value).type
  ensure
    @current_class = old_class
    @current_namespace_override = old_namespace
  end

  def __test_generic_identity_dispatch_owner(type : Adamas::HIR::TypeRef) : String
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = "GenericIdentityScope::Probe"
    @current_namespace_override = "GenericIdentityScope"
    canonical_method_owner_name(get_type_name_from_ref(type))
  ensure
    @current_class = old_class
    @current_namespace_override = old_namespace
  end

  def __test_generic_identity_resolved_ref(name : String) : Adamas::HIR::TypeRef
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = "GenericIdentityScope::Probe"
    @current_namespace_override = "GenericIdentityScope"
    type_ref_for_resolved_name(name)
  ensure
    @current_class = old_class
    @current_namespace_override = old_namespace
  end

  def __test_materialize_generic_identity : Nil
    old_eager = @eager_monomorphization
    begin
      @eager_monomorphization = true
      flush_pending_monomorphizations
    ensure
      @eager_monomorphization = old_eager
    end
  end

  def __test_generic_identity_constructor_arity(type : Adamas::HIR::TypeRef, arity : Int32) : Bool
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = "GenericIdentityScope::Probe"
    @current_namespace_override = "GenericIdentityScope"
    constructor_source_positional_arity_rejected?(get_type_name_from_ref(type), arity)
  ensure
    @current_class = old_class
    @current_namespace_override = old_namespace
  end

  def __test_generic_identity_method(type : Adamas::HIR::TypeRef) : String
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = "GenericIdentityScope::Probe"
    @current_namespace_override = "GenericIdentityScope"
    function = @module.create_function("generic_identity_probe", Adamas::HIR::TypeRef::VOID)
    receiver = function.add_param("receiver", type)
    context = Adamas::HIR::LoweringContext.new(function, @module, @arena)
    context.register_type(receiver.id, type)
    resolve_method_call(context, receiver.id, "value", [] of Adamas::HIR::TypeRef, false)
  ensure
    @current_class = old_class
    @current_namespace_override = old_namespace
  end

  def __test_generic_identity_inherited_methods(type : Adamas::HIR::TypeRef) : {String?, String?, Bool}
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = "GenericIdentityScope::Probe"
    @current_namespace_override = "GenericIdentityScope"
    owner = get_type_name_from_ref(type)
    {resolve_method_with_inheritance(owner, "value"),
     resolve_class_method_with_inheritance(owner, "marker"),
     class_method_declared_in_ancestry?(owner, "marker")}
  ensure
    @current_class = old_class
    @current_namespace_override = old_namespace
  end
end

private def generic_instance_root_identity_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class GenericIdentityChild
    end

    class GenericIdentityBox(T)
      def initialize(@value : T)
      end

      def value : T
        @value
      end

      def self.marker
        1
      end
    end

    module GenericIdentityScope
      class GenericIdentityChild
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
  converter.seed_top_level_type_names([
    "GenericIdentityChild", "GenericIdentityBox", "GenericIdentityScope",
  ])
  converter.seed_top_level_class_kinds([
    {"GenericIdentityChild", false}, {"GenericIdentityBox", false},
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

describe "generic instance root identity" do
  it "retains canonical generic children when recovering a resolved allocator owner" do
    converter = generic_instance_root_identity_converter
    root_box = converter.__test_generic_identity_type_ref("GenericIdentityBox(::GenericIdentityChild)")
    converter.__test_materialize_generic_identity
    owner = converter.module.get_type_descriptor(root_box).not_nil!.name
    converter.__test_generic_identity_resolved_ref(owner).should eq(root_box)
  end

  it "uses the selected owner for instance and class inheritance lookup" do
    converter = generic_instance_root_identity_converter
    root_box = converter.__test_generic_identity_type_ref("GenericIdentityBox(::GenericIdentityChild)")
    converter.__test_materialize_generic_identity
    owner = converter.module.get_type_descriptor(root_box).not_nil!.name
    converter.__test_generic_identity_inherited_methods(root_box).should eq({
      "#{owner}#value", "#{owner}.marker", true,
    })
  end

  it "dispatches a resolved instance receiver without rebinding its generic child" do
    converter = generic_instance_root_identity_converter
    root_box = converter.__test_generic_identity_type_ref("GenericIdentityBox(::GenericIdentityChild)")
    converter.__test_materialize_generic_identity
    method_name = converter.__test_generic_identity_method(root_box)
    method_name.should start_with("#{converter.module.get_type_descriptor(root_box).not_nil!.name}#value")
    method_name.should_not contain("GenericIdentityScope::GenericIdentityChild")
  end

  it "checks source constructor arity on the selected owner in a shadowing namespace" do
    converter = generic_instance_root_identity_converter
    root_box = converter.__test_generic_identity_type_ref("GenericIdentityBox(::GenericIdentityChild)")
    converter.__test_materialize_generic_identity
    converter.__test_generic_identity_constructor_arity(root_box, 1).should be_false
    converter.__test_generic_identity_constructor_arity(root_box, 0).should be_true
    converter.__test_generic_identity_constructor_arity(root_box, 2).should be_true
  end

  it "retains a resolved generic receiver when normalizing its dispatch owner" do
    converter = generic_instance_root_identity_converter
    root_box = converter.__test_generic_identity_type_ref("GenericIdentityBox(::GenericIdentityChild)")
    converter.__test_generic_identity_dispatch_owner(root_box).should eq(
      converter.module.get_type_descriptor(root_box).not_nil!.name,
    )
  end

  it "builds a Hash from resolved child identities without a second lexical lookup" do
    converter = generic_instance_root_identity_converter
    root_child = converter.__test_generic_identity_type_ref("::GenericIdentityChild")
    local_child = converter.__test_generic_identity_type_ref("GenericIdentityChild", "GenericIdentityScope")
    root_child.should_not eq(local_child)

    hash = converter.__test_generic_identity_hash(root_child, Adamas::HIR::TypeRef::INT32)
    converter.module.get_type_descriptor(hash).not_nil!.type_params.should eq([
      root_child, Adamas::HIR::TypeRef::INT32,
    ])
    local_hash = converter.__test_generic_identity_type_ref("Hash(GenericIdentityChild, Int32)", "GenericIdentityScope")
    local_hash.should_not eq(hash)
    converter.module.get_type_descriptor(local_hash).not_nil!.type_params.should eq([
      local_child, Adamas::HIR::TypeRef::INT32,
    ])
  end

  it "coalesces root-relative and explicit-root argument spellings independent of request order" do
    requests = [
      {"GenericIdentityBox(GenericIdentityChild)", "GenericIdentityBox(::GenericIdentityChild)"},
      {"GenericIdentityBox(::GenericIdentityChild)", "GenericIdentityBox(GenericIdentityChild)"},
    ]

    requests.each do |order|
      converter = generic_instance_root_identity_converter
      first = converter.__test_generic_identity_type_ref(order[0])
      second = converter.__test_generic_identity_type_ref(order[1])
      first.should_not eq(Adamas::HIR::TypeRef::VOID)
      first.should eq(second)

      first_descriptor = converter.module.get_type_descriptor(first).not_nil!
      second_descriptor = converter.module.get_type_descriptor(second).not_nil!
      first_descriptor.should eq(second_descriptor)
      first_descriptor.name.should eq(second_descriptor.name)
      first_descriptor.type_params.should eq([
        converter.__test_generic_identity_type_ref("GenericIdentityChild"),
      ])

      converter.__test_materialize_generic_identity
      family = converter.__test_generic_identity_box_family
      family.size.should eq(1)
      family.should contain(first_descriptor.name)
    end
  end

  it "keeps an explicit root child distinct from a same-named namespace child" do
    converter = generic_instance_root_identity_converter
    root_child = converter.__test_generic_identity_type_ref("::GenericIdentityChild", "GenericIdentityScope")
    relative_child = converter.__test_generic_identity_type_ref("GenericIdentityChild", "GenericIdentityScope")
    qualified_child = converter.__test_generic_identity_type_ref(
      "GenericIdentityScope::GenericIdentityChild", "GenericIdentityScope",
    )
    root_child.should_not eq(relative_child)
    relative_child.should eq(qualified_child)

    explicit_root = converter.__test_generic_identity_type_ref(
      "GenericIdentityBox(::GenericIdentityChild)", "GenericIdentityScope",
    )
    relative = converter.__test_generic_identity_type_ref(
      "GenericIdentityBox(GenericIdentityChild)", "GenericIdentityScope",
    )
    qualified = converter.__test_generic_identity_type_ref(
      "GenericIdentityBox(GenericIdentityScope::GenericIdentityChild)", "GenericIdentityScope",
    )
    explicit_root.should_not eq(relative)
    relative.should eq(qualified)

    root_descriptor = converter.module.get_type_descriptor(explicit_root).not_nil!
    relative_descriptor = converter.module.get_type_descriptor(relative).not_nil!
    qualified_descriptor = converter.module.get_type_descriptor(qualified).not_nil!
    root_descriptor.type_params.should eq([root_child])
    relative_descriptor.type_params.should eq([relative_child])
    qualified_descriptor.should eq(relative_descriptor)
  end

  it "keeps class-valued arguments distinct from instance-valued arguments" do
    converter = generic_instance_root_identity_converter
    instance_type = converter.__test_generic_identity_type_ref(
      "GenericIdentityBox(GenericIdentityChild)",
    )
    class_type = converter.__test_generic_identity_type_ref(
      "GenericIdentityBox(GenericIdentityChild.class)",
    )

    instance_type.should_not eq(class_type)
    instance_descriptor = converter.module.get_type_descriptor(instance_type).not_nil!
    class_descriptor = converter.module.get_type_descriptor(class_type).not_nil!
    instance_descriptor.name.should_not eq(class_descriptor.name)
  end

  it "preserves numeric size arguments and canonical builtin Array identity" do
    converter = generic_instance_root_identity_converter
    relative_array = converter.__test_generic_identity_type_ref("Array(GenericIdentityChild)")
    rooted_array = converter.__test_generic_identity_type_ref("Array(::GenericIdentityChild)")
    relative_array.should eq(rooted_array)

    static_four = converter.__test_generic_identity_type_ref("StaticArray(GenericIdentityChild, 4)")
    static_eight = converter.__test_generic_identity_type_ref("StaticArray(GenericIdentityChild, 8)")
    static_four.should_not eq(static_eight)
    converter.module.get_type_descriptor(static_four).not_nil!.name.should_not eq(
      converter.module.get_type_descriptor(static_eight).not_nil!.name,
    )
  end
end
