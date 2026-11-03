require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_run_source_record_prepass(node : Adamas::Compiler::Frontend::ClassNode) : Nil
    owner = safe_slice_to_string(node.name) || ""
    owner_type = @module.intern_type(
      Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, owner),
    )
    @class_info[owner] = ClassInfo.new(owner, owner_type, [] of IVarInfo, [] of ClassVarInfo, 0)
    old_class = @current_class
    @current_class = owner
    begin
      record_constants_in_body(owner, node.body || [] of Adamas::Compiler::Frontend::ExprId)
    ensure
      @current_class = old_class
    end
  end

  def __test_prepass_constant_present?(name : String) : Bool
    @constant_literal_values.has_key?(name)
  end

  def __test_prepass_classvar(owner : String, name : String) : Tuple(Bool, TypeRef?, Int64?)
    class_var = nil.as(ClassVarInfo?)
    if info = @class_info[owner]?
      class_var = info.class_vars.find(&.name.==(name))
    elsif vars = @module_class_vars[owner]?
      class_var = vars.find(&.name.==(name))
    end
    { !class_var.nil?, class_var.try(&.type), class_var.try(&.initial_value) }
  end

  def __test_prepass_class_known?(name : String) : Bool
    @class_info.has_key?(name) || @record_only_source_type_kinds.has_key?(name)
  end

  def __test_prepass_type_kind(name : String) : TypeKind?
    @record_only_source_type_kinds[name]?
  end

  def __test_prepass_type_published?(name : String) : Bool
    @class_info.has_key?(name) || @module_defs.has_key?(name)
  end

  def __test_prepass_include_published?(name : String) : Bool
    @class_included_modules.has_key?(name) || @class_include_instantiations.has_key?(name)
  end

  def __test_prepass_has_deferred_classvar_init?(owner : String) : Bool
    @deferred_classvar_inits.any? { |init| init.owner_class == owner }
  end

  def __test_run_record_prepass_conflict(
    node : Adamas::Compiler::Frontend::ClassNode,
    conflict_name : String,
  ) : Tuple(String?, String?, String?, UInt64, UInt64)
    owner = safe_slice_to_string(node.name) || ""
    owner_type = @module.intern_type(
      Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, owner),
    )
    @class_info[owner] = ClassInfo.new(owner, owner_type, [] of IVarInfo, [] of ClassVarInfo, 0)

    conflict_type = @module.intern_type(
      Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, conflict_name),
    )
    @class_info[conflict_name] = ClassInfo.new(conflict_name, conflict_type, [] of IVarInfo, [] of ClassVarInfo, 0)

    old_class = @current_class
    old_namespace_override = @current_namespace_override
    old_arena = @arena
    @current_class = owner
    @current_namespace_override = "RecordOnlyFailureNamespaceSentinel"

    error_message = nil.as(String?)
    observed_class = nil.as(String?)
    observed_namespace = nil.as(String?)
    observed_arena_id = 0_u64
    expected_arena_id = @arena.object_id.to_u64
    begin
      record_constants_in_body(owner, node.body || [] of Adamas::Compiler::Frontend::ExprId)
    rescue error : LoweringError
      error_message = error.message
      observed_class = @current_class
      observed_namespace = @current_namespace_override
      observed_arena_id = @arena.object_id.to_u64
    ensure
      @current_class = old_class
      @current_namespace_override = old_namespace_override
      @arena = old_arena
    end
    {error_message, observed_class, observed_namespace, observed_arena_id, expected_arena_id}
  end

  def __test_prepass_method_registered?(owner : String, method_name : String) : Bool
    base_name = "#{owner}##{method_name}"
    @function_defs.keys.any? do |name|
      name == base_name || name.starts_with?("#{base_name}$") || name.starts_with?("#{base_name}_previous")
    end
  end

  def __test_register_enum_base_method(
    node : Adamas::Compiler::Frontend::DefNode,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    register_type_method_from_def(node, "Enum", arena)
  end

  def __test_attach_methods_to_registered_enums : Nil
    attach_enum_instance_methods_to_registered_enums
  end

  def __test_publish_enum_body(
    node : Adamas::Compiler::Frontend::EnumNode,
    enum_name : String,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    old_arena = @arena
    @arena = arena
    begin
      register_enum_with_name(node, enum_name)
    ensure
      @arena = old_arena
    end
  end

  def __test_prepass_enum_registered?(name : String) : Bool
    @enum_info.try(&.has_key?(name)) || false
  end

  def __test_prepass_enum_base_type(name : String) : TypeRef?
    @enum_base_types.try(&.[name]?)
  end

  def __test_prepass_enum_member_value(name : String, member : String) : Int64?
    @enum_info.try(&.[name]?).try(&.[member]?)
  end

  def __test_prepass_module_include_count(owner : String) : Int32
    @class_included_modules[owner]?.try(&.size) || 0
  end

  def __test_prepass_type_descriptor_kind(name : String) : TypeKind?
    type_ref = type_ref_for_name(name)
    @module.get_type_descriptor(type_ref).try(&.kind)
  end
end

private def record_only_macro_fixture(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.arena = program.arena

  program.roots.each do |root_id|
    case node = program.arena[root_id]
    when Adamas::Compiler::Frontend::MacroDefNode
      converter.register_macro(node)
    when Adamas::Compiler::Frontend::ClassNode
      # Exercise only the source record-time discovery boundary. Do not call
      # register_class, which publishes the original class body by design.
      converter.__test_run_source_record_prepass(node)
    else
      raise "unexpected record-only macro fixture root #{node.class}"
    end
  end

  converter
end

private def record_only_macro_failure_fixture(
  source : String,
  conflict_name : String,
) : Tuple(String?, String?, String?, UInt64, UInt64)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.arena = program.arena

  observation = nil.as(Tuple(String?, String?, String?, UInt64, UInt64)?)
  program.roots.each do |root_id|
    case node = program.arena[root_id]
    when Adamas::Compiler::Frontend::MacroDefNode
      converter.register_macro(node)
    when Adamas::Compiler::Frontend::ClassNode
      observation = converter.__test_run_record_prepass_conflict(node, conflict_name)
    else
      raise "unexpected record-only failure fixture root #{node.class}"
    end
  end

  observation || raise "record-only failure fixture had no owner class"
end

describe "record-only macro discovery side effects" do
  it "records class-variable metadata from an expanded conditional macro" do
    converter = record_only_macro_fixture(<<-CRYSTAL)
      macro emit_prepass_metadata
        {% if true %}
          RECORD_ONLY_PREPASS_VALUE = 65
          @@record_only_prepass_count : Int32 = 66
          def record_only_prepass_marker : Int32
            67
          end
        {% end %}
      end

      class RecordOnlyPrepassMetadataOwner
        {% if true %}
          emit_prepass_metadata()
        {% end %}
      end
    CRYSTAL

    converter.__test_prepass_constant_present?(
      "RecordOnlyPrepassMetadataOwner::RECORD_ONLY_PREPASS_VALUE",
    ).should be_true
    present, type, initial_value = converter.__test_prepass_classvar(
      "RecordOnlyPrepassMetadataOwner",
      "record_only_prepass_count",
    )
    present.should be_true
    type.should eq(Adamas::HIR::TypeRef::INT32)
    initial_value.should eq(66_i64)
  end

  it "does not publish a flat generated method during record-only discovery" do
    converter = record_only_macro_fixture(<<-CRYSTAL)
      macro emit_flat_method
        {% if true %}
          RECORD_ONLY_FLAT_VALUE = 65
          def record_only_flat_marker : Int32
            67
          end
        {% end %}
      end

      class RecordOnlyFlatMethodOwner
        {% if true %}
          emit_flat_method()
        {% end %}
      end
    CRYSTAL

    converter.__test_prepass_constant_present?(
      "RecordOnlyFlatMethodOwner::RECORD_ONLY_FLAT_VALUE",
    ).should be_true
    converter.__test_prepass_method_registered?(
      "RecordOnlyFlatMethodOwner",
      "record_only_flat_marker",
    ).should be_false
  end

  it "discovers a nested type emitted by a conditional macro" do
    converter = record_only_macro_fixture(<<-CRYSTAL)
      macro emit_nested_type
        class Inner
          def value : Int32
            65
          end
        end
      end

      class RecordOnlyNestedTypeOwner
        {% if true %}
          emit_nested_type()
        {% end %}
      end
    CRYSTAL

    converter.__test_prepass_class_known?("RecordOnlyNestedTypeOwner::Inner").should be_true
  end

  it "does not publish nested methods while discovering the emitted type" do
    converter = record_only_macro_fixture(<<-CRYSTAL)
      macro emit_nested_type
        class Inner
          def value : Int32
            65
          end
        end
      end

      class RecordOnlyNestedMethodOwner
        {% if true %}
          emit_nested_type()
        {% end %}
      end
    CRYSTAL

    converter.__test_prepass_class_known?("RecordOnlyNestedMethodOwner::Inner").should be_true
    converter.__test_prepass_method_registered?(
      "RecordOnlyNestedMethodOwner::Inner",
      "value",
    ).should be_false
  end

  it "records enum metadata without publishing enum body methods" do
    converter = record_only_macro_fixture(<<-CRYSTAL)
      macro emit_enum_with_method
        enum Mode
          Ready
          One = 4

          {% if true %}
            def record_only_enum_conditional_marker : Int32
              66
            end
          {% end %}

          def record_only_enum_marker : Int32
            65
          end
        end
      end

      class RecordOnlyEnumMethodOwner
        {% if true %}
          emit_enum_with_method()
        {% end %}
      end
    CRYSTAL

    converter.__test_prepass_enum_registered?(
      "RecordOnlyEnumMethodOwner::Mode",
    ).should be_true
    converter.__test_prepass_enum_base_type(
      "RecordOnlyEnumMethodOwner::Mode",
    ).should eq(Adamas::HIR::TypeRef::INT32)
    converter.__test_prepass_enum_member_value(
      "RecordOnlyEnumMethodOwner::Mode",
      "Ready",
    ).should eq(0_i64)
    converter.__test_prepass_enum_member_value(
      "RecordOnlyEnumMethodOwner::Mode",
      "One",
    ).should eq(4_i64)
    converter.__test_prepass_module_include_count(
      "RecordOnlyEnumMethodOwner::Mode",
    ).should eq(0)
    converter.__test_prepass_method_registered?(
      "RecordOnlyEnumMethodOwner::Mode",
      "record_only_enum_marker",
    ).should be_false
    converter.__test_prepass_method_registered?(
      "RecordOnlyEnumMethodOwner::Mode",
      "record_only_enum_conditional_marker",
    ).should be_false
  end

  it "keeps enum-wide inherited attachment deferred until enum body publication" do
    converter = record_only_macro_fixture(<<-CRYSTAL)
      macro emit_enum
        enum Mode
          Ready
        end
      end

      class RecordOnlyEnumMethodOwner
        {% if true %}
          emit_enum()
        {% end %}
      end
    CRYSTAL

    base_method_program = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(<<-CRYSTAL)
        def inherited_record_only_marker : Int32
          65
        end
      CRYSTAL
    ).parse_program
    base_method_program.roots.size.should eq(1)
    base_method = base_method_program.arena[base_method_program.roots.first].as(
      Adamas::Compiler::Frontend::DefNode
    )
    converter.__test_register_enum_base_method(base_method, base_method_program.arena)

    enum_name = "RecordOnlyEnumMethodOwner::Mode"
    converter.__test_prepass_enum_registered?(enum_name).should be_true
    converter.__test_attach_methods_to_registered_enums
    converter.__test_prepass_method_registered?(
      enum_name,
      "inherited_record_only_marker",
    ).should be_false

    publish_program = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(<<-CRYSTAL)
        enum Mode
          Ready
        end
      CRYSTAL
    ).parse_program
    publish_program.roots.size.should eq(1)
    publish_enum = publish_program.arena[publish_program.roots.first].as(
      Adamas::Compiler::Frontend::EnumNode
    )
    converter.__test_publish_enum_body(publish_enum, enum_name, publish_program.arena)
    converter.__test_prepass_method_registered?(
      enum_name,
      "inherited_record_only_marker",
    ).should be_true
  end

  it "discovers nested module and class metadata without publishing their bodies or includes" do
    converter = record_only_macro_fixture(<<-CRYSTAL)
      macro emit_nested_metadata
        module Container
          module IncludeTarget
            macro included
              @@record_only_include_effect : Int32 = 103
            end

            def included_marker : Int32
              43
            end
          end

          @@container_count : Int32 = 47
          CONTAINER_VALUE = 53

          module NestedModule
            @@module_count : Int32 = 59
            @@module_label : String = "record-only"
            MODULE_VALUE = 61
            def module_marker : Int32
              67
            end

            class NestedClass
              @@class_count : Int32 = 71
              CLASS_VALUE = 73
              include IncludeTarget
              def class_marker : Int32
                79
              end

              module DeepModule
                @@deep_count : Int32 = 83
                @@assigned_count = 97
                DEEP_VALUE = 89
                def deep_marker : Int32
                  101
                end
              end
            end
          end
        end
      end

      class RecordOnlyNestedMetadataOwner
        {% if true %}
          emit_nested_metadata()
        {% end %}
      end
    CRYSTAL

    container = "RecordOnlyNestedMetadataOwner::Container"
    include_target = "#{container}::IncludeTarget"
    nested_module = "#{container}::NestedModule"
    nested_class = "#{nested_module}::NestedClass"
    deep_module = "#{nested_class}::DeepModule"

    {
      {container, Adamas::HIR::TypeKind::Module},
      {include_target, Adamas::HIR::TypeKind::Module},
      {nested_module, Adamas::HIR::TypeKind::Module},
      {nested_class, Adamas::HIR::TypeKind::Class},
      {deep_module, Adamas::HIR::TypeKind::Module},
    }.each do |name, kind|
      converter.__test_prepass_type_kind(name).should eq(kind)
      converter.__test_prepass_type_published?(name).should be_false
      converter.__test_prepass_type_descriptor_kind(name).should eq(kind)
    end

    {
      {container, "container_count", 47_i64},
      {nested_module, "module_count", 59_i64},
      {nested_class, "class_count", 71_i64},
      {deep_module, "deep_count", 83_i64},
      {deep_module, "assigned_count", 97_i64},
    }.each do |owner, name, initial_value|
      present, type, observed_initial_value = converter.__test_prepass_classvar(owner, name)
      present.should be_true
      type.should eq(Adamas::HIR::TypeRef::INT32)
      observed_initial_value.should eq(initial_value)
      converter.__test_prepass_has_deferred_classvar_init?(owner).should be_false
    end
    present, type, initial_value = converter.__test_prepass_classvar(nested_module, "module_label")
    present.should be_true
    type.should eq(Adamas::HIR::TypeRef::STRING)
    initial_value.should be_nil
    converter.__test_prepass_has_deferred_classvar_init?(nested_module).should be_false

    {
      "#{container}::CONTAINER_VALUE",
      "#{nested_module}::MODULE_VALUE",
      "#{nested_class}::CLASS_VALUE",
      "#{deep_module}::DEEP_VALUE",
    }.each do |name|
      converter.__test_prepass_constant_present?(name).should be_true
    end

    converter.__test_prepass_method_registered?(include_target, "included_marker").should be_false
    converter.__test_prepass_method_registered?(nested_module, "module_marker").should be_false
    converter.__test_prepass_method_registered?(nested_class, "class_marker").should be_false
    converter.__test_prepass_method_registered?(deep_module, "deep_marker").should be_false
    converter.__test_prepass_module_include_count(nested_class).should eq(0)
    converter.__test_prepass_include_published?(nested_class).should be_false
    include_effect, _, _ = converter.__test_prepass_classvar(nested_class, "record_only_include_effect")
    include_effect.should be_false
  end

  it "restores the caller's namespace and source arena when a nested kind conflict raises" do
    source = <<-CRYSTAL
      macro emit_conflicting_nested_type
        class Inner
          module Collision
          end
        end
      end

      class RecordOnlyFailureOwner
        {% if true %}
          emit_conflicting_nested_type()
        {% end %}
      end
    CRYSTAL
    message, observed_class, observed_namespace, observed_arena_id, expected_arena_id =
      record_only_macro_failure_fixture(source, "RecordOnlyFailureOwner::Inner::Collision")
    message.should_not be_nil
    message.not_nil!.should start_with("record-only source type kind conflict")
    observed_class.should eq("RecordOnlyFailureOwner")
    observed_namespace.should eq("RecordOnlyFailureNamespaceSentinel")
    observed_arena_id.should eq(expected_arena_id)
  end
end
