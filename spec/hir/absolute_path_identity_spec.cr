require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_type_literal_receiver_identity(
    call_id : Adamas::Compiler::Frontend::ExprId,
    namespace : String,
  ) : {String?, String?, String?}
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = "#{namespace}::Runner"
    @current_namespace_override = namespace
    call = @arena[call_id].as(Adamas::Compiler::Frontend::CallNode)
    receiver = @arena[call.callee].as(Adamas::Compiler::Frontend::MemberAccessNode).object
    inferred = infer_type_from_expr(receiver, @current_class)
    {infer_type_literal_name_from_expr(receiver), source_call_receiver_name(call, @current_class),
     inferred.try { |type| get_type_name_from_ref(type) }}
  ensure
    @current_class = old_class
    @current_namespace_override = old_namespace
  end

  def __test_inferred_root_call_result(
    call_id : Adamas::Compiler::Frontend::ExprId,
    namespace : String,
  ) : String?
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = "#{namespace}::Runner"
    @current_namespace_override = namespace
    infer_type_from_expr(call_id, @current_class).try { |type| get_type_name_from_ref(type) }
  ensure
    @current_class = old_class
    @current_namespace_override = old_namespace
  end

  def __test_canonical_bound_type_ref(name : String) : Adamas::HIR::TypeRef
    canonical_bound_type_ref(name)
  end

  def __test_canonical_union_variant_refs(type_ref : Adamas::HIR::TypeRef) : Array(Adamas::HIR::TypeRef)
    ensure_union_descriptor_for_type_ref(type_ref)
    union_descriptor_from_sidecar(type_ref).not_nil!.variants.map do |variant|
      mir_to_hir_type_ref(variant.type_ref)
    end
  end
end

describe "absolute type-literal receiver identity" do
  it "keeps a root identity through cold inference and source call binding" do
    source = <<-CRYSTAL
      class RootReceiverIdentity
      end
      module ReceiverIdentityScope
        class RootReceiverIdentity
        end
        class Runner
        end
      end
      ::RootReceiverIdentity.marker()
      RootReceiverIdentity.marker()
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source),
    )
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    calls = [] of Adamas::Compiler::Frontend::ExprId
    program.roots.each do |id|
      case node = arena[id]
      when Adamas::Compiler::Frontend::ClassNode
        converter.register_class(node)
      when Adamas::Compiler::Frontend::ModuleNode
        converter.register_module(node)
      when Adamas::Compiler::Frontend::CallNode
        calls << id
      end
    end
    calls.size.should eq(2)
    converter.__test_type_literal_receiver_identity(calls[0], "ReceiverIdentityScope")
      .should eq({"RootReceiverIdentity", "RootReceiverIdentity", "RootReceiverIdentity"})
    converter.__test_type_literal_receiver_identity(calls[1], "ReceiverIdentityScope")
      .should eq({"ReceiverIdentityScope::RootReceiverIdentity", "ReceiverIdentityScope::RootReceiverIdentity", "ReceiverIdentityScope::RootReceiverIdentity"})
  end

  it "does not replace a rooted enum receiver with a same-named nested module" do
    source = <<-CRYSTAL
      enum RootEnumReceiverIdentity
        First
      end
      module EnumReceiverIdentityScope
        module RootEnumReceiverIdentity
        end
        class Runner
        end
      end
      ::RootEnumReceiverIdentity.each()
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    call = nil.as(Adamas::Compiler::Frontend::ExprId?)
    program.roots.each do |id|
      case node = arena[id]
      when Adamas::Compiler::Frontend::EnumNode
        converter.register_enum(node)
      when Adamas::Compiler::Frontend::ModuleNode
        converter.register_module(node)
      when Adamas::Compiler::Frontend::CallNode
        call = id
      end
    end
    converter.__test_type_literal_receiver_identity(call.not_nil!, "EnumReceiverIdentityScope")
      .should eq({"RootEnumReceiverIdentity", "RootEnumReceiverIdentity", "RootEnumReceiverIdentity"})
  end

  it "expands a rooted alias head without reopening lexical namespace lookup" do
    source = <<-CRYSTAL
      module RootPathAliasTarget
        class Inner
        end
      end
      alias RootPathAliasIdentity = RootPathAliasTarget
      module RootPathAliasIdentityScope
        module RootPathAliasIdentity
          class Inner
          end
        end
        class Runner
        end
      end
      ::RootPathAliasIdentity::Inner.marker()
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    call = nil.as(Adamas::Compiler::Frontend::ExprId?)
    program.roots.each do |id|
      case node = arena[id]
      when Adamas::Compiler::Frontend::ModuleNode
        converter.register_module(node)
      when Adamas::Compiler::Frontend::AliasNode
        converter.register_alias(node)
      when Adamas::Compiler::Frontend::CallNode
        call = id
      end
    end
    converter.__test_type_literal_receiver_identity(call.not_nil!, "RootPathAliasIdentityScope")
      .should eq({"RootPathAliasTarget::Inner", "RootPathAliasTarget::Inner", "RootPathAliasTarget::Inner"})
  end

  it "expands a qualified root alias component without selecting a local same-spelled path" do
    source = <<-CRYSTAL
      module RootQualifiedAliasNamespace
        module Target
          class Inner
          end
        end
        alias NestedAlias = Target
      end
      module RootQualifiedAliasIdentityScope
        module RootQualifiedAliasNamespace
          module NestedAlias
            class Inner
            end
          end
        end
        class Runner
        end
      end
      ::RootQualifiedAliasNamespace::NestedAlias::Inner.marker()
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    calls = [] of Adamas::Compiler::Frontend::ExprId
    program.roots.each do |id|
      case node = arena[id]
      when Adamas::Compiler::Frontend::ModuleNode
        converter.register_module(node)
      when Adamas::Compiler::Frontend::CallNode
        calls << id
      end
    end
    calls.size.should eq(1)
    expected = {"RootQualifiedAliasNamespace::Target::Inner", "RootQualifiedAliasNamespace::Target::Inner",
                "RootQualifiedAliasNamespace::Target::Inner"}
    calls.each do |call|
      converter.__test_type_literal_receiver_identity(call, "RootQualifiedAliasIdentityScope").should eq(expected)
    end
  end

  it "binds a selected root class call's self block parameter to its resolved owner" do
    source = <<-CRYSTAL
      enum RootCallbackReceiverIdentity
        First
        def self.echo(&block : self -> U) : U forall U
          yield new(0)
        end
      end
      module CallbackReceiverIdentityScope
        module RootCallbackReceiverIdentity
        end
        class Runner
        end
      end
      ::RootCallbackReceiverIdentity.echo { |value| value }
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    call = nil.as(Adamas::Compiler::Frontend::ExprId?)
    program.roots.each do |id|
      case node = arena[id]
      when Adamas::Compiler::Frontend::EnumNode
        converter.register_enum(node)
      when Adamas::Compiler::Frontend::ModuleNode
        converter.register_module(node)
      when Adamas::Compiler::Frontend::CallNode
        call = id
      end
    end
    converter.__test_inferred_root_call_result(call.not_nil!, "CallbackReceiverIdentityScope")
      .should eq("RootCallbackReceiverIdentity")
  end
end

private def absolute_identity_composite_fixture
  source = <<-CRYSTAL
    enum RootBoundIdentity
      First
    end
    module BoundIdentityScope
      module RootBoundIdentity
      end
      class Box(T)
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::EnumNode
      converter.register_enum(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end
  root_enum = converter.__test_canonical_bound_type_ref("RootBoundIdentity")
  nested_module = converter.__test_canonical_bound_type_ref("BoundIdentityScope::RootBoundIdentity")
  {converter, root_enum, nested_module}
end

describe "canonical bound composite identity" do
  it "keeps the rooted enum TypeRef in tuple, named tuple, nullable, union, and generic children" do
    converter, root_enum, nested_module = absolute_identity_composite_fixture
    root_enum.should_not eq(nested_module)
    converter.module.get_type_descriptor(root_enum).not_nil!.kind.should eq(Adamas::HIR::TypeKind::Struct)
    converter.module.get_type_descriptor(nested_module).not_nil!.kind.should eq(Adamas::HIR::TypeKind::Module)

    tuple = converter.module.get_type_descriptor(
      converter.__test_canonical_bound_type_ref("Tuple(RootBoundIdentity)"),
    ).not_nil!
    tuple.kind.should eq(Adamas::HIR::TypeKind::Tuple)
    tuple.type_params.should eq([root_enum])

    named_tuple = converter.module.get_type_descriptor(
      converter.__test_canonical_bound_type_ref("NamedTuple(value: RootBoundIdentity)"),
    ).not_nil!
    named_tuple.kind.should eq(Adamas::HIR::TypeKind::NamedTuple)
    named_tuple.type_params.should eq([root_enum])

    nullable_ref = converter.__test_canonical_bound_type_ref("RootBoundIdentity?")
    nullable = converter.module.get_type_descriptor(nullable_ref).not_nil!
    nullable.kind.should eq(Adamas::HIR::TypeKind::Union)
    nullable_variants = converter.__test_canonical_union_variant_refs(nullable_ref)
    nullable_variants.should contain(root_enum)
    nullable_variants.should contain(Adamas::HIR::TypeRef::NIL)

    union_ref = converter.__test_canonical_bound_type_ref(
      "RootBoundIdentity | BoundIdentityScope::RootBoundIdentity",
    )
    union = converter.module.get_type_descriptor(union_ref).not_nil!
    union.kind.should eq(Adamas::HIR::TypeKind::Union)
    union_variants = converter.__test_canonical_union_variant_refs(union_ref)
    union_variants.should contain(root_enum)
    union_variants.should contain(nested_module)

    generic = converter.module.get_type_descriptor(
      converter.__test_canonical_bound_type_ref("BoundIdentityScope::Box(RootBoundIdentity)"),
    ).not_nil!
    generic.type_params.should eq([root_enum])
  end

  it "anchors both Proc input and result TypeRefs and retains literal-slot facts" do
    converter, root_enum, nested_module = absolute_identity_composite_fixture
    proc_type = converter.__test_canonical_bound_type_ref(
      "Proc(RootBoundIdentity.class, BoundIdentityScope::RootBoundIdentity.class)",
    )
    proc = converter.module.get_type_descriptor(proc_type).not_nil!
    proc.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc.type_params.should eq([root_enum, nested_module])
    proc.proc_type_literal_slot?(0).should be_true
    proc.proc_type_literal_slot?(1).should be_true

    mixed_proc_type = converter.__test_canonical_bound_type_ref(
      "Proc(RootBoundIdentity.class, BoundIdentityScope::RootBoundIdentity)",
    )
    mixed_proc = converter.module.get_type_descriptor(mixed_proc_type).not_nil!
    mixed_proc.type_params.should eq([root_enum, nested_module])
    mixed_proc.proc_type_literal_slot?(0).should be_true
    mixed_proc.proc_type_literal_slot?(1).should be_false
  end

  it "canonicalizes a grouped multi-input Proc arrow without treating the group as a type name" do
    converter, root_enum, nested_module = absolute_identity_composite_fixture
    proc_type = converter.__test_canonical_bound_type_ref(
      "(RootBoundIdentity.class, BoundIdentityScope::RootBoundIdentity) -> RootBoundIdentity.class",
    )
    proc = converter.module.get_type_descriptor(proc_type).not_nil!
    proc.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc.type_params.should eq([root_enum, nested_module, root_enum])
    proc.proc_type_literal_slot?(0).should be_true
    proc.proc_type_literal_slot?(1).should be_false
    proc.proc_type_literal_slot?(2).should be_true
  end

  it "canonicalizes a NamedTuple Proc-arrow shorthand input and keeps its rooted child" do
    converter, root_enum, nested_module = absolute_identity_composite_fixture
    proc_type = converter.__test_canonical_bound_type_ref(
      "{value: BoundIdentityScope::RootBoundIdentity.class} -> RootBoundIdentity.class",
    )
    proc = converter.module.get_type_descriptor(proc_type).not_nil!
    proc.kind.should eq(Adamas::HIR::TypeKind::Proc)
    proc.type_params.size.should eq(2)
    proc.proc_type_literal_slot?(0).should be_false
    proc.proc_type_literal_slot?(1).should be_true

    named_tuple = converter.module.get_type_descriptor(proc.type_params[0]).not_nil!
    named_tuple.kind.should eq(Adamas::HIR::TypeKind::NamedTuple)
    named_tuple.type_params.should eq([nested_module])
    named_tuple.name.should contain("BoundIdentityScope::RootBoundIdentity.class")
    proc.type_params[1].should eq(root_enum)
  end
end
