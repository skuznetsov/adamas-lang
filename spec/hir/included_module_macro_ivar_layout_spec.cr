require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_macro_ivar_default_literal(owner : String, name : String) : String?
    field = @class_info[owner].ivars.find(&.name.==(name))
    source = field.try(&.default_source)
    return nil unless source
    Adamas::Compiler::Frontend.node_literal_string(source.arena[source.expr_id])
  end

  def __test_macro_ivar_default_owner(owner : String, name : String) : String?
    @class_info[owner].ivars.find(&.name.==(name)).try(&.default_source).try(&.lexical_owner)
  end

  def __test_macro_ivar_type_name(owner : String, name : String) : String
    field = @class_info[owner].ivars.find(&.name.==(name)).not_nil!
    get_type_name_from_ref(field.type)
  end

  def __test_macro_method_return_annotations(owner : String, name : String) : Array(String)
    prefix = "#{owner}##{name}"
    @function_defs.compact_map do |key, definition|
      next unless key == prefix || key.starts_with?("#{prefix}$")
      definition.return_type.try { |type| safe_slice_to_string(type) }
    end
  end

  def __test_macro_constant_registered?(name : String) : Bool
    @constant_defs.includes?(name) || @constant_literal_values.has_key?(name)
  end

  def __test_macro_class_registered?(name : String) : Bool
    @class_info.has_key?(name) || @module_defs.has_key?(name)
  end

  def __test_macro_branch_node_kinds(source : String) : Array(String)
    parsed = parse_macro_literal_class_body(source)
    return [] of String unless parsed
    parsed_arena, body_ids = parsed
    with_arena(parsed_arena) do
      body_ids.map { |body_id| @arena[body_id].class.name.split("::").last }
    end
  end
end

private def module_macro_ivar_converter(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node, root_id)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    else
      raise "unexpected module macro ivar fixture root #{node.class}"
    end
  end
  converter
end

describe "conditional ivar declarations in included modules" do
  it "registers only active branches across reopenings and keeps the layout owner-local" do
    source = <<-CRYSTAL
      module PlatformMacroIvarMixin
        @direct_slot : Bool
      end

      module PlatformMacroIvarMixin
        {% if flag?(:win32) %}
          @windows_slot : UInt8 = 1
        {% elsif flag?(:darwin) %}
          @darwin_slot : Int32 = 2
        {% else %}
          @other_slot : Int64 = 3
        {% end %}

        {% if flag?(:win32) %}
          @windows_only_slot : UInt16
        {% else %}
          @not_windows_slot : UInt32
        {% end %}

      end

      class PlatformMacroIvarOwner
        include PlatformMacroIvarMixin
      end

      class PlatformMacroIvarSecondOwner
        include PlatformMacroIvarMixin
      end

      class PlatformMacroIvarControl
      end
    CRYSTAL
    converter = module_macro_ivar_converter(source)

    selected_name = {% if flag?(:win32) %} "@windows_slot" {% elsif flag?(:darwin) %} "@darwin_slot" {% else %} "@other_slot" {% end %}
    selected_type = {% if flag?(:win32) %} Adamas::HIR::TypeRef::UINT8 {% elsif flag?(:darwin) %} Adamas::HIR::TypeRef::INT32 {% else %} Adamas::HIR::TypeRef::INT64 {% end %}
    false_branch_name = {% if flag?(:win32) %} "@windows_only_slot" {% else %} "@not_windows_slot" {% end %}
    false_branch_type = {% if flag?(:win32) %} Adamas::HIR::TypeRef::UINT16 {% else %} Adamas::HIR::TypeRef::UINT32 {% end %}
    active_names = ["@direct_slot", selected_name, false_branch_name]

    {"PlatformMacroIvarOwner", "PlatformMacroIvarSecondOwner"}.each do |owner_name|
      fields = converter.class_info[owner_name].ivars
      field_names = fields.map(&.name)
      active_names.each { |name| field_names.should contain(name) }
      field_names.size.should eq(active_names.size)
      fields.find(&.name.==("@direct_slot")).not_nil!.type.should eq(Adamas::HIR::TypeRef::BOOL)
      fields.find(&.name.==(selected_name)).not_nil!.type.should eq(selected_type)
      fields.find(&.name.==(false_branch_name)).not_nil!.type.should eq(false_branch_type)
      converter.__test_macro_ivar_default_literal(owner_name, selected_name).should eq(
        {% if flag?(:win32) %} "1" {% elsif flag?(:darwin) %} "2" {% else %} "3" {% end %},
      )
      {"@windows_slot", "@darwin_slot", "@other_slot"}.each do |name|
        field_names.should_not contain(name) unless name == selected_name
      end
      {"@windows_only_slot", "@not_windows_slot"}.each do |name|
        field_names.should_not contain(name) unless name == false_branch_name
      end
    end

    converter.class_info["PlatformMacroIvarControl"].ivars.should be_empty
  end

  it "resolves postfix pointer fields and generic field types for each include" do
    source = <<-CRYSTAL
      module PointerMacroIvarMixin
        {% if flag?(:darwin) %}
          @pointer_slot : Int32*
        {% else %}
          @pointer_slot : Int32*
        {% end %}
      end

      module TypedMacroIvarMixin(T)
        {% if flag?(:darwin) %}
          @typed_slot : T
        {% else %}
          @typed_slot : T
        {% end %}
      end

      class PointerMacroIvarOwner
        include PointerMacroIvarMixin
      end

      class Int32MacroIvarOwner
        include TypedMacroIvarMixin(Int32)
      end

      class StringMacroIvarOwner
        include TypedMacroIvarMixin(String)
      end
    CRYSTAL
    converter = module_macro_ivar_converter(source)

    pointer_fields = converter.class_info["PointerMacroIvarOwner"].ivars
    pointer_fields.map(&.name).should eq(["@pointer_slot"])
    converter.module.get_type_descriptor(pointer_fields.first.type).not_nil!.name.should eq("Pointer(Int32)")

    int_fields = converter.class_info["Int32MacroIvarOwner"].ivars
    int_fields.map(&.name).should eq(["@typed_slot"])
    converter.__test_macro_ivar_type_name("Int32MacroIvarOwner", "@typed_slot").should eq("Int32")

    string_fields = converter.class_info["StringMacroIvarOwner"].ivars
    string_fields.map(&.name).should eq(["@typed_slot"])
    converter.__test_macro_ivar_type_name("StringMacroIvarOwner", "@typed_slot").should eq("String")
  end

  it "does not turn local or class-variable type declarations into instance fields" do
    branch = <<-CRYSTAL
      @slot : Int32 = 5
      scratch : Int32 = 1
      @@shared : Int32 = 2
    CRYSTAL
    converter = module_macro_ivar_converter(<<-CRYSTAL)
      module MacroDeclarationKindMixin
        {% if flag?(:darwin) %}
          @slot : Int32 = 5
          scratch : Int32 = 1
          @@shared : Int32 = 2
        {% else %}
          @slot : Int32 = 5
          scratch : Int32 = 1
          @@shared : Int32 = 2
        {% end %}
      end

      class MacroDeclarationKindOwner
        include MacroDeclarationKindMixin
      end
    CRYSTAL

    converter.__test_macro_branch_node_kinds(branch).should eq([
      "InstanceVarDeclNode",
      "TypeDeclarationNode",
      "ClassVarDeclNode",
    ])
    converter.class_info["MacroDeclarationKindOwner"].ivars.map(&.name).should eq(["@slot"])
  end

  it "registers an untyped instance assignment from an active module macro branch" do
    converter = module_macro_ivar_converter(<<-CRYSTAL)
      module UntypedMacroIvarMixin
        {% if flag?(:darwin) %}
          @assigned_slot = 1
        {% else %}
          @assigned_slot = 1
        {% end %}
      end

      class UntypedMacroIvarOwner
        include UntypedMacroIvarMixin
      end
    CRYSTAL

    fields = converter.class_info["UntypedMacroIvarOwner"].ivars
    fields.map(&.name).should eq(["@assigned_slot"])
    converter.__test_macro_ivar_type_name("UntypedMacroIvarOwner", "@assigned_slot").should eq("Int32")
  end

  it "does not re-own declarations adjacent to the selected field" do
    source = <<-CRYSTAL
      module MacroBranchOwnerGuard
        module C
          class Nested
          end
        end

        {% if flag?(:darwin) %}
          @lexical_slot : C::Nested = C::Nested.new
          def marker : Int32
            1
          end
          SIDE_EFFECT = 1
          module C
            class BranchOnly
            end
          end
        {% else %}
          @lexical_slot : C::Nested = C::Nested.new
          def marker : String
            "branch"
          end
          SIDE_EFFECT = 2
          module C
            class BranchOnly
            end
          end
        {% end %}

        {% if MacroBranchOwnerGuardUnknownCondition %}
          def undecidable_method_only
            "@not_an_instance_field"
          end
        {% end %}
      end

      class MacroBranchOwnerGuardOwner
        def marker : Bool
          true
        end
        include MacroBranchOwnerGuard
      end
    CRYSTAL
    converter = module_macro_ivar_converter(source)

    fields = converter.class_info["MacroBranchOwnerGuardOwner"].ivars
    fields.map(&.name).should eq(["@lexical_slot"])
    field_type = converter.module.get_type_descriptor(fields.first.type).not_nil!.name
    field_type.should eq("MacroBranchOwnerGuard::C::Nested")
    converter.__test_macro_ivar_default_owner("MacroBranchOwnerGuardOwner", "@lexical_slot").should eq("MacroBranchOwnerGuard")

    converter.__test_macro_method_return_annotations("MacroBranchOwnerGuardOwner", "marker").should contain("Bool")
    converter.__test_macro_method_return_annotations("MacroBranchOwnerGuardOwner", "marker").should_not contain("String")
    converter.__test_macro_method_return_annotations("MacroBranchOwnerGuardOwner", "marker").should_not contain("Int32")
    converter.__test_macro_constant_registered?("MacroBranchOwnerGuardOwner::SIDE_EFFECT").should be_false
    converter.__test_macro_class_registered?("MacroBranchOwnerGuardOwner::C").should be_false
    converter.__test_macro_class_registered?("MacroBranchOwnerGuardOwner::C::BranchOnly").should be_false
  end
end
