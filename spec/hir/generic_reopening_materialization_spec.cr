require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_materialize_before_generic_reopening(name : String) : Adamas::HIR::TypeRef
    old_defer = @defer_monomorphization
    begin
      @defer_monomorphization = false
      type_ref_for_name(name)
    ensure
      @defer_monomorphization = old_defer
    end
  end

  def __test_materialize_generic_eager(name : String) : Adamas::HIR::TypeRef
    old_eager = @eager_monomorphization
    begin
      @eager_monomorphization = true
      type_ref_for_name(name)
    ensure
      @eager_monomorphization = old_eager
    end
  end

  def __test_generic_reopening_selected_method(name : String) : String?
    lookup_function_def_for_call(
      "#{name}#late", 1, false, [Adamas::HIR::TypeRef::UINT64],
    ).try(&.[0])
  end

  def __test_generic_reopening_class_method(name : String, arg_type : Adamas::HIR::TypeRef) : String?
    lookup_function_def_for_call(name, 1, false, [arg_type]).try(&.[0])
  end

  def __test_generic_reopening_result_annotation(name : String) : String?
    lookup_function_def_for_call(
      "#{name}#late", 1, false, [Adamas::HIR::TypeRef::UINT64],
    ).try { |entry| entry[1].return_type.try { |text| String.new(text) } }
  end

  def __test_generic_reopening_class_var_count(name : String) : Int32
    @class_info[name].class_vars.count { |var| var.name == "counter" }
  end

  def __test_lower_generic_reopening_method(name : String) : Nil
    lower_function_if_needed(name)
  end

  def __test_generic_reopening_returned_integer(name : String) : Int64?
    function = @module.function_by_name(name)
    return unless function

    return_value = nil.as(Adamas::HIR::ValueId?)
    function.blocks.each do |block|
      if ret = block.terminator.as?(Adamas::HIR::Return)
        return_value = ret.value
      end
    end
    return unless value_id = return_value

    value = function.blocks.flat_map(&.instructions).find { |instruction| instruction.id == value_id }
    value.try(&.as?(Adamas::HIR::Literal)).try(&.int_value)
  end

  def __test_expect_generic_reopening_integer_method(
    owner : String,
    method_name : String,
    arg_type : Adamas::HIR::TypeRef,
    expected : Int64,
  ) : Nil
    target = __test_generic_reopening_class_method("#{owner}.#{method_name}", arg_type).not_nil!
    __test_lower_generic_reopening_method(target)
    __test_generic_reopening_returned_integer(target).should eq(expected)
  end

  def __test_generate_generic_reopening_allocator(name : String) : Nil
    generate_allocator(name, @class_info[name], force: true)
  end

  def __test_generic_reopening_allocator_fields(name : String) : Array(String)
    function = @module.function_by_name("#{name}.new")
    return [] of String unless function

    function.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::FieldSet).try(&.field_name)
    end
  end

  def __test_generic_reopening_function(name : String) : Adamas::HIR::Function?
    @module.function_by_name(name)
  end

  def __test_generate_source_bound_allocator(
    owner : String,
    arg_types : Array(Adamas::HIR::TypeRef),
    named_arg_names : Array(String),
  ) : String
    init_base = resolve_method_with_inheritance(owner, "initialize").not_nil!
    selected = allocator_initializer_def_for(
      init_base, init_base, arg_types, false, true, named_arg_names,
    ).not_nil!
    selected_target = SelectedCallTarget.new(selected[0], selected[1], selected[2])
    target = allocator_generated_target_name_for_call(
      owner, arg_types, true, false, named_arg_names, selected_target,
    )
    generate_allocator(
      owner, @class_info[owner], arg_types,
      call_has_named_args: true,
      call_named_arg_names: named_arg_names,
      selected_initializer: true,
      selected_init_target: selected_target,
    )
    target
  end

  def __test_generic_reopening_function_fields(name : String) : Array(String)
    function = @module.function_by_name(name)
    return [] of String unless function

    function.blocks.flat_map(&.instructions).compact_map do |instruction|
      instruction.as?(Adamas::HIR::FieldSet).try(&.field_name)
    end
  end

  def __test_flush_deferred_allocator_layout_recipes : Nil
    flush_deferred_allocators
  end

  def __test_deferred_allocator_layout_target?(name : String) : Bool
    @deferred_allocator_overload_targets.includes?(name)
  end

  def __test_generic_reopening_field_get_offset(name : String, field_name : String) : Int32?
    function = @module.function_by_name(name)
    return unless function

    function.blocks.flat_map(&.instructions).compact_map do |instruction|
      field_get = instruction.as?(Adamas::HIR::FieldGet)
      field_get.field_offset if field_get && field_get.field_name == field_name
    end.first?
  end

  # A generic declaration normally changes every specialization. This helper
  # models a layout delta already isolated to one concrete owner so the test
  # can assert that sibling bodies and allocators retain their exact identity.
  def __test_generic_reopening_change_exact_layout(name : String, field_name : String) : Nil
    info = @class_info[name]
    ivars = info.ivars.dup
    ivars << Adamas::HIR::IVarInfo.new(field_name, Adamas::HIR::TypeRef::INT32, info.size)
    updated = Adamas::HIR::ClassInfo.new(
      info.name, info.type_ref, ivars, info.class_vars, info.size + 4,
      info.is_struct, info.parent_name,
    )
    @class_info[name] = updated
    @class_info_by_type_id[info.type_ref.id] = updated
    bump_class_info_version
    invalidate_lowered_layout_functions(name, exact_owner_only: true)
  end
end

describe "materialized generic reopening" do
  {"Box(Int32)" => "class Box(T)", "Pointer(Void)" => "struct Pointer(T)"}.each do |instance, header|
    it "publishes later source methods to an already materialized #{instance}" do
      source = <<-CRYSTAL
        #{header}
        end

        #{header}
          def late(boundary : UInt64) : T
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
      converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))
      before = converter.__test_materialize_before_generic_reopening(instance)
      converter.__test_generic_reopening_selected_method(instance).should be_nil
      converter.register_class(arena[program.roots[1]].as(Adamas::Compiler::Frontend::ClassNode))
      converter.__test_materialize_before_generic_reopening(instance).should eq(before)
      converter.__test_generic_reopening_selected_method(instance).should eq("#{instance}#late$UInt64")
      # Replaying the same immutable source declaration cannot revoke the
      # completed specialization or lose the newly published method.
      converter.register_class(arena[program.roots[1]].as(Adamas::Compiler::Frontend::ClassNode))
      converter.__test_generic_reopening_selected_method(instance).should eq("#{instance}#late$UInt64")
    end
  end

  it "applies replacements in source order for warm and cold concrete families" do
    source = <<-CRYSTAL
      class OrderedBox(T)
        @@counter : Int32 = 1
        def late(boundary : UInt64) : Int32
          1
        end
      end

      class OrderedBox(T)
        def late(boundary : UInt64) : String
          "latest"
        end
        def extra_one
        end
        def extra_two
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
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.__test_materialize_before_generic_reopening("OrderedBox(Int32)")
    converter.__test_generic_reopening_result_annotation("OrderedBox(Int32)").should eq("Int32")
    converter.register_class(arena[program.roots[1]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.__test_materialize_before_generic_reopening("OrderedBox(String)")
    {"OrderedBox(Int32)", "OrderedBox(String)"}.each do |name|
      converter.__test_generic_reopening_result_annotation(name).should eq("String")
      converter.__test_generic_reopening_class_var_count(name).should eq(1)
    end
  end

  it "eagerly lowers only the registered definition for each exact overload" do
    source = <<-CRYSTAL
      class EagerReopenBox(T)
        def self.pick(value : Int32) : Int32
          1
        end
        def self.pick(value : String) : Int32
          2
        end
      end

      class EagerReopenBox(T)
        def self.pick(value : Bool) : Int32
          3
        end
      end

      class EagerReopenBox(T)
        def self.pick(value : Int32) : Int32
          4
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
    program.roots.each do |root|
      converter.register_class(arena[root].as(Adamas::Compiler::Frontend::ClassNode))
    end

    converter.__test_materialize_generic_eager("EagerReopenBox(Int32)")
    converter.__test_materialize_generic_eager("EagerReopenBox(String)")
    converter.__test_materialize_generic_eager("EagerReopenBox(Bool)")

    converter.__test_expect_generic_reopening_integer_method(
      "EagerReopenBox(Int32)", "pick", Adamas::HIR::TypeRef::INT32, 4_i64,
    )
    converter.__test_expect_generic_reopening_integer_method(
      "EagerReopenBox(String)", "pick", Adamas::HIR::TypeRef::STRING, 2_i64,
    )
    converter.__test_expect_generic_reopening_integer_method(
      "EagerReopenBox(Bool)", "pick", Adamas::HIR::TypeRef::BOOL, 3_i64,
    )
  end

  it "replaces an already lowered method body when a later reopening redefines it" do
    source = <<-CRYSTAL
      class ReopenBox(T)
        def late(boundary : UInt64) : Int32
          1
        end
      end

      class ReopenBox(T)
        def late(boundary : UInt64) : Int32
          2
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
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.__test_materialize_before_generic_reopening("ReopenBox(Int32)")

    target = "ReopenBox(Int32)#late$UInt64"
    converter.__test_lower_generic_reopening_method(target)
    converter.__test_generic_reopening_returned_integer(target).should eq(1_i64)

    converter.register_class(arena[program.roots[1]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.__test_lower_generic_reopening_method(target)
    converter.__test_generic_reopening_returned_integer(target).should eq(2_i64)
  end

  it "keeps a lowered generic class-method alias for a sibling overload but replaces its exact redefinition" do
    source = <<-CRYSTAL
      class AliasBox(T)
        def self.pick(value : Int32) : Int32
          1
        end
      end

      class AliasBox(T)
        def self.pick(value : String) : Int32
          2
        end
      end

      class AliasBox(T)
        def self.pick(value : Int32) : Int32
          3
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
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))

    # This is the ordinary bare generic class-method lookup path. It publishes
    # and selects the base-owner alias before any concrete specialization exists.
    target = "AliasBox.pick$Int32"
    converter.__test_generic_reopening_class_method(
      "AliasBox.pick", Adamas::HIR::TypeRef::INT32,
    ).should eq(target)
    converter.__test_lower_generic_reopening_method(target)
    original = converter.__test_generic_reopening_function(target).not_nil!
    converter.__test_generic_reopening_returned_integer(target).should eq(1_i64)

    converter.__test_materialize_before_generic_reopening("AliasBox(Int32)")
    converter.register_class(arena[program.roots[1]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.__test_lower_generic_reopening_method(target)
    converter.__test_generic_reopening_function(target).not_nil!.same?(original).should be_true
    converter.__test_generic_reopening_returned_integer(target).should eq(1_i64)

    # Replacing the same signature is different from adding a sibling overload:
    # the old source body must be discarded and the exact alias re-lowered.
    converter.register_class(arena[program.roots[2]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.__test_lower_generic_reopening_method(target)
    replacement = converter.__test_generic_reopening_function(target).not_nil!
    replacement.same?(original).should be_false
    converter.__test_generic_reopening_returned_integer(target).should eq(3_i64)
  end

  it "refreshes an existing allocator after a reopening adds a generic ivar" do
    source = <<-CRYSTAL
      class LayoutBox(T)
        @before : Int32 = 1
      end

      class LayoutBox(T)
        @added : T = 2
      end
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    converter.arena = arena
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.__test_materialize_before_generic_reopening("LayoutBox(Int32)")
    converter.__test_generate_generic_reopening_allocator("LayoutBox(Int32)")

    converter.__test_generic_reopening_allocator_fields("LayoutBox(Int32)").should contain("@before")
    converter.__test_generic_reopening_allocator_fields("LayoutBox(Int32)").should_not contain("@added")

    converter.register_class(arena[program.roots[1]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.class_info["LayoutBox(Int32)"].ivars.map(&.name).should contain("@added")
    converter.__test_generate_generic_reopening_allocator("LayoutBox(Int32)")
    converter.__test_generic_reopening_allocator_fields("LayoutBox(Int32)").should contain("@added")
  end

  it "replays the exact source-bound private allocator target after a layout reopening" do
    source = <<-CRYSTAL
      class BoundLayoutBox(T)
        @before : Int32 = 1

        def initialize(value : Int32, *, enabled : Bool)
          @before = value
          @enabled = enabled
        end
      end

      class BoundLayoutBox(T)
        @late : T = 2
      end
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    converter.arena = arena
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.__test_materialize_before_generic_reopening("BoundLayoutBox(Int32)")

    target = converter.__test_generate_source_bound_allocator(
      "BoundLayoutBox(Int32)",
      [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::BOOL],
      ["enabled"],
    )
    target.should contain(".__adamas_allocator_new")
    original = converter.__test_generic_reopening_function(target).not_nil!
    converter.__test_generic_reopening_function_fields(target).should contain("@before")
    converter.__test_generic_reopening_function_fields(target).should_not contain("@late")

    converter.register_class(arena[program.roots[1]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.class_info["BoundLayoutBox(Int32)"].ivars.map(&.name).should contain("@late")
    converter.__test_deferred_allocator_layout_target?(target).should be_true
    converter.__test_flush_deferred_allocator_layout_recipes

    replayed = converter.__test_generic_reopening_function(target).not_nil!
    replayed.same?(original).should be_false
    converter.__test_generic_reopening_function_fields(target).should contain("@late")
    converter.__test_deferred_allocator_layout_target?(target).should be_false
  end

  it "updates a registered child's inherited layout, lowered field offset, and allocator after a parent reopening" do
    source = <<-CRYSTAL
      class LayoutParent(T)
        @before : Int32 = 1
      end

      class LayoutChild < LayoutParent(Int32)
        @child : Int32 = 2
        def child_value(boundary : UInt64) : Int32
          @child
        end
      end

      class LayoutParent(T)
        @late : T = 3
      end
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    converter.arena = arena
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.__test_materialize_before_generic_reopening("LayoutParent(Int32)")
    converter.register_class(arena[program.roots[1]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.fixup_inherited_ivars

    target = "LayoutChild#child_value$UInt64"
    converter.__test_lower_generic_reopening_method(target)
    converter.__test_generic_reopening_field_get_offset(target, "@child").should eq(8)
    converter.__test_generate_generic_reopening_allocator("LayoutChild")
    converter.__test_generic_reopening_allocator_fields("LayoutChild").should contain("@before")
    converter.__test_generic_reopening_allocator_fields("LayoutChild").should contain("@child")
    converter.__test_generic_reopening_allocator_fields("LayoutChild").should_not contain("@late")

    converter.register_class(arena[program.roots[2]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.class_info["LayoutChild"].ivars.map(&.name).should contain("@late")
    converter.__test_lower_generic_reopening_method(target)
    converter.__test_generic_reopening_field_get_offset(target, "@child").should eq(12)
    converter.__test_generate_generic_reopening_allocator("LayoutChild")
    converter.__test_generic_reopening_allocator_fields("LayoutChild").should contain("@late")
  end

  it "preserves an already lowered sibling body and allocator when only Int32 layout changes" do
    source = <<-CRYSTAL
      class SiblingBox(T)
        @value : T
        def late(boundary : UInt64) : T
          @value
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
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.__test_materialize_before_generic_reopening("SiblingBox(Int32)")
    converter.__test_materialize_before_generic_reopening("SiblingBox(String)")

    target = "SiblingBox(String)#late$UInt64"
    allocator = "SiblingBox(String).new"
    converter.__test_lower_generic_reopening_method(target)
    converter.__test_generate_generic_reopening_allocator("SiblingBox(String)")
    original_body = converter.__test_generic_reopening_function(target).not_nil!
    original_allocator = converter.__test_generic_reopening_function(allocator).not_nil!

    converter.__test_generic_reopening_change_exact_layout("SiblingBox(Int32)", "@int32_only")

    converter.__test_generic_reopening_function(target).not_nil!.same?(original_body).should be_true
    converter.__test_generic_reopening_function(allocator).not_nil!.same?(original_allocator).should be_true
  end

  it "rejects a bare generic class method whose selected body reads an unbound owner formal" do
    source = <<-CRYSTAL
      class BareBodyFormal(T)
        def self.value
          T
        end
      end

      BareBodyFormal.value
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    converter.arena = arena
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))

    expect_raises(Adamas::HIR::LoweringError, /can't infer the type parameter T/) do
      converter.lower_main([program.roots.last.index.to_u64])
    end
  end

  it "rejects a parenthesized bare generic class call whose body reads an unbound owner formal" do
    source = <<-CRYSTAL
      class BareBodyCallFormal(T)
        def self.value
          T
        end
      end

      BareBodyCallFormal.value()
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    converter.arena = arena
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))

    expect_raises(Adamas::HIR::LoweringError, /can't infer the type parameter T/) do
      converter.lower_main([program.roots.last.index.to_u64])
    end
  end

  it "allows a bare generic class method independent of its owner's formals" do
    source = <<-CRYSTAL
      class BareIndependent(T)
        def self.value : Int32
          65
        end
      end

      BareIndependent.value
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    converter.arena = arena
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.lower_main([program.roots.last.index.to_u64])
  end

  it "lets a method forall shadow a same-named generic owner formal" do
    source = <<-CRYSTAL
      class BareForallShadow(T)
        def self.identity(value : T) : T forall T
          value
        end
      end

      BareForallShadow.identity(65)
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    converter.arena = arena
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.lower_main([program.roots.last.index.to_u64])
  end

  it "does not treat an absolute ::T type path as an unbound owner formal" do
    source = <<-CRYSTAL
      class T
        def code : Int32
          65
        end
      end

      class BareQualifiedFormal(T)
        def self.value : ::T
          ::T.new
        end
      end

      BareQualifiedFormal.value.code
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    converter.arena = arena
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.register_class(arena[program.roots[1]].as(Adamas::Compiler::Frontend::ClassNode))
    converter.lower_main([program.roots.last.index.to_u64])
  end

  it "does not treat a specialized generic class-method receiver as a bare owner" do
    source = <<-CRYSTAL
      class SpecializedOwnerFormal(T)
        def self.value
          T
        end
      end

      SpecializedOwnerFormal(Int32).value
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
    converter.no_prelude = true
    converter.arena = arena
    converter.register_class(arena[program.roots[0]].as(Adamas::Compiler::Frontend::ClassNode))

    converter.lower_main([program.roots.last.index.to_u64])
  end
end
