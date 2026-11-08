require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

private record PropertySetterSourceObservation,
  target_name : String,
  call_type_name : String,
  parameter_annotation : String?,
  result_facts : Array({String, Bool}),
  body_emitted : Bool,
  source_definition_matches : Bool,
  source_arena_matches : Bool,
  source_definition_id : UInt64?

class Adamas::HIR::AstToHir
  def __test_seed_incompatible_property_setter_source(target_name : String) : Nil
    source_def = @function_defs[target_name]? || raise "missing exact setter source Def for #{target_name}"
    source_arena = @function_def_arenas[target_name]? || raise "missing exact setter source Arena for #{target_name}"

    # Keep the registered source Def/Arena exact while making the prior
    # physical-name receipt differ from the ordinary setter binding.
    prior = ForceLowerExactSourceBinding.new(
      source_def, source_arena, target_name, false, "#{target_name}#stale-physical",
    )
    selected = ForceLowerExactSourceBinding.new(source_def, source_arena, target_name)
    force_lower_exact_source_matches?(target_name, prior).should be_true
    same_force_lower_exact_source_binding?(prior, selected).should be_false
    @force_lower_replay_source_bindings[target_name] = prior
  end

  def __test_property_setter_route(
    caller_name : String,
  ) : Tuple(PropertySetterSourceObservation, PropertySetterSourceObservation)
    caller = @module.function_by_name(caller_name) ||
             raise "missing lowered setter caller #{caller_name}"
    calls = caller.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))

    setter = calls.find do |call|
      strip_type_suffix(call.method_name) == "SetterReplayBox#value="
    end || raise "missing emitted value= call in #{caller_name}"
    picker = calls.find do |call|
      strip_type_suffix(call.method_name) == "SetterReplayBox#pick"
    end || raise "missing emitted pick call in #{caller_name}"

    {__test_property_setter_target_observation(setter.method_name, setter.type),
     __test_property_setter_target_observation(picker.method_name, picker.type)}
  end

  private def __test_property_setter_target_observation(
    target_name : String,
    call_type : Adamas::HIR::TypeRef,
  ) : PropertySetterSourceObservation
    function = @module.function_by_name(target_name) ||
               raise "missing lowered source target #{target_name}"
    definition = @function_defs[target_name]? ||
                 raise "missing exact source Def for #{target_name}"
    declaration_arena = @function_def_arenas[target_name]? ||
                        raise "missing exact source Arena for #{target_name}"
    first_param = definition.params.try(&.first?)
    parameter_annotation = first_param.try { |param| parameter_type_annotation_string(param, declaration_arena) }
    facts = (function.source_return_value_facts || [] of {Adamas::HIR::TypeRef, Bool}).map do |(type, literal)|
      {get_type_name_from_ref(type), literal}
    end

    PropertySetterSourceObservation.new(
      target_name,
      get_type_name_from_ref(call_type),
      parameter_annotation,
      facts,
      function.blocks.any?(&.body_emitted),
      function.source_return_definition_id == definition.object_id.to_u64,
      function.source_return_arena_key == arena_map_key(declaration_arena),
      function.source_return_definition_id,
    )
  end
end

private def property_setter_chain_source : String
  String.build do |io|
    {"class", "instance"}.each do |route|
      10.times do |index|
        io << "def #{route}_route_chain#{index}(box : SetterReplayBox)\n"
        if index == 9
          io << "  box.#{route}_route\n"
        else
          io << "  #{route}_route_chain#{index + 1}(box)\n"
        end
        io << "end\n"
      end
    end
  end
end

private def lower_property_setter_source(
  source : String,
  conflicting_source_target : String? = nil,
) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  raise "parser diagnostics: #{parser.diagnostics.size}" unless parser.diagnostics.empty?

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
    paths_by_arena: {arena.object_id.to_u64 => "/tmp/property_setter_source_result_spec.cr"},
  )
  converter.no_prelude = true

  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  definitions = [] of Adamas::Compiler::Frontend::DefNode
  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      definitions << node
    else
      main << id.index.to_u64
    end
  end

  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  definitions.each { |node| converter.register_function(node) }
  # Mirror the CLI registration-before-demand lifecycle. Eagerly lowering
  # uncalled bodies supplies no call-selected parameter source facts and would
  # inspect a different materialization path from property-setter replay.
  if target = conflicting_source_target
    converter.__test_seed_incompatible_property_setter_source(target)
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

private def property_setter_source_fixture(call_order : Array(String)) : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class SetterReplayBox
      def value=(value : Int32)
        value
      end

      def value=(value : Int32.class)
        value
      end

      def pick(value : Int32) : Int32
        65
      end

      def pick(value : Int32.class) : Int32
        66
      end

      def instance_route : Int32
        self.pick(self.value = 1)
      end

      def class_route : Int32
        self.pick(self.value = Int32)
      end
    end

    #{property_setter_chain_source}

    box = SetterReplayBox.new
    #{call_order.join("\n")}
  CRYSTAL
  lower_property_setter_source(source)
end

describe "property setter source result ownership" do
  {
    "instance call first" => ["instance_route_chain0(box)", "class_route_chain0(box)"],
    "class call first" => ["class_route_chain0(box)", "instance_route_chain0(box)"],
  }.each do |order, calls|
    it "retains the exact setter and result kind through replay when #{order}" do
      converter = property_setter_source_fixture(calls)
      instance_setter, instance_picker = converter.__test_property_setter_route(
        "SetterReplayBox#instance_route",
      )
      class_setter, class_picker = converter.__test_property_setter_route(
        "SetterReplayBox#class_route",
      )

      instance_setter.parameter_annotation.should eq("Int32")
      instance_setter.call_type_name.should eq("Int32")
      instance_setter.result_facts.should eq([{"Int32", false}])
      class_setter.parameter_annotation.should eq("Int32.class")
      class_setter.call_type_name.should eq("Int32")
      class_setter.result_facts.should eq([{"Int32", true}])

      instance_setter.target_name.should_not eq(class_setter.target_name)
      instance_setter.source_definition_id.should_not eq(class_setter.source_definition_id)
      instance_setter.source_definition_matches.should be_true
      instance_setter.source_arena_matches.should be_true
      class_setter.source_definition_matches.should be_true
      class_setter.source_arena_matches.should be_true
      instance_setter.body_emitted.should be_true
      class_setter.body_emitted.should be_true

      # The setter calls share the Int32 ABI carrier. The following overload
      # must still see the result's source kind and select its corresponding
      # declaration after the exact setter body has been materialized.
      instance_picker.parameter_annotation.should eq("Int32")
      class_picker.parameter_annotation.should eq("Int32.class")
      instance_picker.call_type_name.should eq("Int32")
      class_picker.call_type_name.should eq("Int32")
      instance_picker.source_definition_matches.should be_true
      instance_picker.source_arena_matches.should be_true
      class_picker.source_definition_matches.should be_true
      class_picker.source_arena_matches.should be_true
    end
  end

  it "rejects an instance value when only a class-object setter exists" do
    expect_raises(Adamas::HIR::LoweringError, /no overload matches/) do
      lower_property_setter_source(<<-CRYSTAL)
        class SetterInputKind
          def value=(value : Int32.class)
            value
          end
        end
        box = SetterInputKind.new
        box.value = 1
      CRYSTAL
    end
  end

  it "rejects a class object when only an instance setter exists" do
    expect_raises(Adamas::HIR::LoweringError, /no overload matches/) do
      lower_property_setter_source(<<-CRYSTAL)
        class SetterInputKindInverse
          def value=(value : Int32)
            value
          end
        end
        box = SetterInputKindInverse.new
        box.value = Int32
      CRYSTAL
    end
  end

  it "does not pass a class-valued setter result to an instance-only consumer" do
    expect_raises(Adamas::HIR::LoweringError, /no overload matches/) do
      lower_property_setter_source(<<-CRYSTAL)
        class SetterResultKind
          def value=(value : Int32)
            Int32
          end
        end
        def consume_instance(value : Int32) : Int32
          65
        end
        box = SetterResultKind.new
        consume_instance(box.value = 1)
      CRYSTAL
    end
  end

  it "rejects a conflicting exact-source scope at the parsed setter call" do
    target_name = "PropertySetterSourceScope#value=$Int32"
    expect_raises(Adamas::HIR::LoweringError, /property setter source changed before result inference/) do
      lower_property_setter_source(<<-CRYSTAL, target_name)
        class PropertySetterSourceScope
          def value=(value : Int32)
            value
          end
        end
        box = PropertySetterSourceScope.new
        box.value = 1
      CRYSTAL
    end
  end
end
