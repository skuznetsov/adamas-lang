require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_defaulted_source_targets(
    source_prefix : String,
    expected_definition : Adamas::Compiler::Frontend::DefNode,
    expected_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Array({String, Bool, Bool, Bool, Bool})
    targets = [] of String
    @module.functions.each do |function|
      function.blocks.each do |block|
        block.instructions.each do |instruction|
          call = instruction.as?(Call) || next
          next unless call.method_name == source_prefix || call.method_name.starts_with?("#{source_prefix}$")
          targets << call.method_name
        end
      end
    end

    targets.uniq.sort.map do |target|
      definition = @function_defs[target]?
      arena = @function_def_arenas[target]?
      function = @module.function_by_name(target)
      {
        target,
        definition.try(&.same?(expected_definition)) == true,
        arena.try { |entry| entry.object_id == expected_arena.object_id } == true,
        function ? @module.has_function_with_body?(target) : false,
        function ? function_state(target).completed? : false,
      }
    end
  end

  def __test_defaulted_source_name(
    target : String,
    expected_definition : Adamas::Compiler::Frontend::DefNode,
    expected_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : String
    @function_defs.each do |name, definition|
      next if name == target
      next unless definition.same?(expected_definition)
      arena = @function_def_arenas[name]?
      return name if arena && arena.same?(expected_arena)
    end
    raise "no separate source entry for #{target}"
  end

  def __test_bind_defaulted_source_call_target(
    target : String,
    selected_name : String,
    selected_def : Adamas::Compiler::Frontend::DefNode,
    selected_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    bind_defaulted_source_call_target(target, selected_name, selected_def, selected_arena)
  end

  def __test_forget_defaulted_target_binding(target : String) : Nil
    @function_defs.delete(target)
    @function_def_arenas.delete(target)
    nil
  end

  def __test_replace_defaulted_target_def(
    target : String,
    definition : Adamas::Compiler::Frontend::DefNode,
  ) : Nil
    @function_defs[target] = definition
    nil
  end

  def __test_replace_defaulted_target_arena(
    target : String,
    arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    @function_def_arenas[target] = arena
    nil
  end

  def __test_defaulted_target_def(target : String) : Adamas::Compiler::Frontend::DefNode?
    @function_defs[target]?
  end

  def __test_defaulted_target_arena(target : String) : Adamas::Compiler::Frontend::ArenaLike?
    @function_def_arenas[target]?
  end
end

private def lower_defaulted_target_source_case(kind : String)
  owner_name, method_name, source, owner_is_module = case kind
                                                      when "module_scalar"
                                                        {
                                                          "DefaultedTargetModuleScalarHIR",
                                                          "prefix",
                                                          <<-CRYSTAL,
                                                            module DefaultedTargetModuleScalarHIR
                                                              def self.prefix(value : Int32, *, group : Int32 = 3_i32, payload = 0_i32) : Int32
                                                                65_i32
                                                              end
                                                              def self.take(value : Int32) : Int32
                                                                value
                                                              end
                                                            end
                                                            DefaultedTargetModuleScalarHIR.take(DefaultedTargetModuleScalarHIR.prefix(3_i32))
                                                            CRYSTAL
                                                          true,
                                                        }
                                                      when "module_tuple"
                                                        {
                                                          "DefaultedTargetModuleTupleHIR",
                                                          "prefix",
                                                          <<-CRYSTAL,
                                                            module DefaultedTargetModuleTupleHIR
                                                              def self.prefix(value : Int32, *, group : Int32 = 3_i32, payload = { {65_i32, 66_i32}, {nil, 67_i32} }) : Int32
                                                                65_i32
                                                              end
                                                              def self.take(value : Int32) : Int32
                                                                value
                                                              end
                                                            end
                                                            DefaultedTargetModuleTupleHIR.take(DefaultedTargetModuleTupleHIR.prefix(3_i32))
                                                            CRYSTAL
                                                          true,
                                                        }
                                                      when "class_member"
                                                        {
                                                          "DefaultedTargetClassMemberHIR",
                                                          "value",
                                                          <<-CRYSTAL,
                                                            class DefaultedTargetClassMemberHIR
                                                              def self.value(seed : Int32 = 65_i32, *, group : Int32 = 3_i32, payload = 0_i32) : Int32
                                                                65_i32
                                                              end
                                                              def self.take(value : Int32) : Int32
                                                                value
                                                              end
                                                            end
                                                            DefaultedTargetClassMemberHIR.take(DefaultedTargetClassMemberHIR.value)
                                                            CRYSTAL
                                                          false,
                                                        }
                                                      when "instance_member"
                                                        {
                                                          "DefaultedTargetInstanceMemberHIR",
                                                          "value",
                                                          <<-CRYSTAL,
                                                            class DefaultedTargetInstanceMemberHIR
                                                              def value(seed : Int32 = 65_i32, *, group : Int32 = 3_i32, payload = 0_i32) : Int32
                                                                65_i32
                                                              end
                                                              def self.take(value : Int32) : Int32
                                                                value
                                                              end
                                                            end
                                                            DefaultedTargetInstanceMemberHIR.new.value
                                                            CRYSTAL
                                                          false,
                                                        }
                                                      when "struct_instance_member"
                                                        {
                                                          "DefaultedTargetStructInstanceMemberHIR",
                                                          "value",
                                                          <<-CRYSTAL,
                                                            struct DefaultedTargetStructInstanceMemberHIR
                                                              def value(seed : Int32 = 65_i32, *, group : Int32 = 3_i32, payload = 0_i32) : Int32
                                                                seed
                                                              end
                                                            end
                                                            def take_defaulted_struct(value : Int32) : Int32
                                                              value
                                                            end
                                                            take_defaulted_struct(DefaultedTargetStructInstanceMemberHIR.new.value)
                                                            CRYSTAL
                                                          false,
                                                        }
                                                      else
                                                        raise "unknown defaulted target case #{kind}"
                                                      end

  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena

  expected_definition = nil.as(Adamas::Compiler::Frontend::DefNode?)
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  defs = [] of Adamas::Compiler::Frontend::DefNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ClassNode
      if !owner_is_module && String.new(node.name) == owner_name
        expected_definition = node.body.not_nil!.compact_map do |member_id|
          arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
        end.find { |definition| String.new(definition.name) == method_name }
      end
      classes << node
    when Adamas::Compiler::Frontend::ModuleNode
      if owner_is_module && String.new(node.name) == owner_name
        expected_definition = node.body.not_nil!.compact_map do |member_id|
          arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
        end.find { |definition| String.new(definition.name) == method_name }
      end
      modules << node
    when Adamas::Compiler::Frontend::DefNode
      defs << node
    else
      main << root_id.index.to_u64
    end
  end

  definition = expected_definition || raise "fixture has no source Def for #{owner_name}.#{method_name}"
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  classes.each { |node| converter.register_class(node) }
  modules.each { |node| converter.register_module(node) }
  defs.each { |node| converter.register_function(node) }
  classes.each { |node| converter.lower_class(node) }
  modules.each { |node| converter.lower_module(node) }
  defs.each { |node| converter.lower_def(node) }
  converter.lower_main(main)
  converter.flush_pending_functions

  prefix = owner_is_module ? "#{owner_name}.#{method_name}" :
                             (kind == "instance_member" || kind == "struct_instance_member" ? "#{owner_name}##{method_name}" : "#{owner_name}.#{method_name}")
  {converter, prefix, definition, arena}
end

describe "defaulted call target source binding" do
  {"module_scalar", "module_tuple", "class_member", "instance_member", "struct_instance_member"}.each do |kind|
    it "publishes exact Def, arena, and completed body for #{kind}" do
      converter, prefix, definition, arena = lower_defaulted_target_source_case(kind)
      targets = converter.__test_defaulted_source_targets(prefix, definition, arena)
      targets.size.should eq(1)
      target = targets.first? || raise "no materialized call target for #{prefix}"
      target[1].should be_true
      target[2].should be_true
      target[3].should be_true
      target[4].should be_true
    end
  end

  it "passes a struct instance result directly to a nonvirtual Int32 consumer" do
    converter, prefix, _, _ = lower_defaulted_target_source_case("struct_instance_member")
    main = converter.module.function_by_name("__adamas_main")
    main.should_not be_nil
    calls = main.not_nil!.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
    value_call = calls.find { |call| call.method_name == prefix || call.method_name.starts_with?("#{prefix}$") }
    value_call.should_not be_nil
    take_call = calls.find { |call| call.method_name.starts_with?("take_defaulted_struct") }
    take_call.should_not be_nil

    value_call = value_call.not_nil!
    take_call = take_call.not_nil!
    value_call.virtual.should be_false
    take_call.virtual.should be_false
    value_call.type.should eq(Adamas::HIR::TypeRef::INT32)
    take_call.type.should eq(Adamas::HIR::TypeRef::INT32)
    take_call.args.should eq([value_call.id])
  end

  it "rejects a foreign Def even when the source name is registered" do
    converter, prefix, definition, arena = lower_defaulted_target_source_case("module_scalar")
    target = converter.__test_defaulted_source_targets(prefix, definition, arena).first?.try(&.[0]) ||
             raise "no materialized call target for #{prefix}"
    source_name = converter.__test_defaulted_source_name(target, definition, arena)
    foreign_parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("def foreign_defaulted_target(value : Int32 = 99_i32); value; end"),
    )
    foreign_program = foreign_parser.parse_program
    foreign_def = foreign_program.roots.compact_map do |root_id|
      foreign_program.arena[root_id].as?(Adamas::Compiler::Frontend::DefNode)
    end.first? || raise "foreign fixture has no Def"

    expect_raises(Adamas::HIR::LoweringError, /exact selected source binding/) do
      converter.__test_bind_defaulted_source_call_target(target, source_name, foreign_def, arena)
    end
  end

  it "rejects a foreign arena for the exact selected Def" do
    converter, prefix, definition, arena = lower_defaulted_target_source_case("module_scalar")
    target = converter.__test_defaulted_source_targets(prefix, definition, arena).first?.try(&.[0]) ||
             raise "no materialized call target for #{prefix}"
    source_name = converter.__test_defaulted_source_name(target, definition, arena)
    foreign_parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("class ForeignDefaultedTargetArena; end"),
    )
    foreign_arena = foreign_parser.parse_program.arena

    expect_raises(Adamas::HIR::LoweringError, /exact selected source binding/) do
      converter.__test_bind_defaulted_source_call_target(target, source_name, definition, foreign_arena)
    end
  end

  it "rejects a conflicting physical target Def without replacing it or the canonical source" do
    converter, prefix, definition, arena = lower_defaulted_target_source_case("module_scalar")
    target = converter.__test_defaulted_source_targets(prefix, definition, arena).first?.try(&.[0]) ||
             raise "no materialized call target for #{prefix}"
    source_name = converter.__test_defaulted_source_name(target, definition, arena)
    foreign_parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("def foreign_defaulted_target(value : Int32 = 99_i32); value; end"),
    )
    foreign_program = foreign_parser.parse_program
    foreign_def = foreign_program.roots.compact_map do |root_id|
      foreign_program.arena[root_id].as?(Adamas::Compiler::Frontend::DefNode)
    end.first? || raise "foreign fixture has no Def"

    converter.__test_replace_defaulted_target_def(target, foreign_def)
    expect_raises(Adamas::HIR::LoweringError, /target already has a different source definition/) do
      converter.__test_bind_defaulted_source_call_target(target, source_name, definition, arena)
    end

    (converter.__test_defaulted_target_def(target).try(&.same?(foreign_def)) == true).should be_true
    (converter.__test_defaulted_target_arena(target).try(&.same?(arena)) == true).should be_true
    converter.__test_defaulted_source_name(target, definition, arena).should eq(source_name)
  end

  it "rejects a conflicting physical target arena without replacing it or the canonical source" do
    converter, prefix, definition, arena = lower_defaulted_target_source_case("module_scalar")
    target = converter.__test_defaulted_source_targets(prefix, definition, arena).first?.try(&.[0]) ||
             raise "no materialized call target for #{prefix}"
    source_name = converter.__test_defaulted_source_name(target, definition, arena)
    foreign_parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("class ForeignDefaultedTargetArena; end"),
    )
    foreign_arena = foreign_parser.parse_program.arena

    converter.__test_replace_defaulted_target_arena(target, foreign_arena)
    expect_raises(Adamas::HIR::LoweringError, /target already has a different source arena/) do
      converter.__test_bind_defaulted_source_call_target(target, source_name, definition, arena)
    end

    (converter.__test_defaulted_target_def(target).try(&.same?(definition)) == true).should be_true
    (converter.__test_defaulted_target_arena(target).try(&.same?(foreign_arena)) == true).should be_true
    converter.__test_defaulted_source_name(target, definition, arena).should eq(source_name)
  end

  it "rejects a completed body after its target Def and arena bindings are removed" do
    converter, prefix, definition, arena = lower_defaulted_target_source_case("module_scalar")
    target = converter.__test_defaulted_source_targets(prefix, definition, arena).first?.try(&.[0]) ||
             raise "no materialized call target for #{prefix}"
    source_name = converter.__test_defaulted_source_name(target, definition, arena)
    source_name.should_not eq(target)

    converter.__test_forget_defaulted_target_binding(target)
    expect_raises(Adamas::HIR::LoweringError, /body has no complete source binding/) do
      converter.__test_bind_defaulted_source_call_target(target, source_name, definition, arena)
    end
  end
end
