require "../spec_helper"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/hir/ast_to_hir"

private record InheritedMemberSourceContractObservation,
  nilary_call_name : String?,
  nilary_call_arg_count : Int32,
  nilary_call_type : Adamas::HIR::TypeRef?,
  nilary_target_source_def : Bool,
  nilary_target_source_arena : Bool,
  nilary_target_return_def_stamp : Bool,
  nilary_target_return_arena_stamp : Bool,
  source_registry_preserved : Bool,
  child_arity_sibling_preserved : Bool,
  child_sibling_return : Adamas::HIR::TypeRef?,
  one_arg_call_name : String?,
  one_arg_call_arg_count : Int32,
  one_arg_call_type : Adamas::HIR::TypeRef?

private record InheritedMemberSourceReceiptObservation,
  receipt_was_current : Bool,
  stale_source_def_rejected : Bool,
  stale_source_arena_rejected : Bool,
  crossed_physical_pair_rejected : Bool,
  same_complete_pair_equal : Bool,
  both_absent_pair_equal : Bool,
  one_sided_def_rejected : Bool,
  one_sided_arena_rejected : Bool,
  one_sided_def_self_rejected : Bool,
  one_sided_arena_self_rejected : Bool,
  crossed_pair_rejected : Bool

class Adamas::HIR::AstToHir
  def __test_register_inherited_member_source_classes(
    parent : Adamas::Compiler::Frontend::ClassNode,
    parent_arena : Adamas::Compiler::Frontend::ArenaLike,
    reference : Adamas::Compiler::Frontend::ClassNode,
    concrete : Adamas::Compiler::Frontend::ClassNode,
    child_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : Nil
    @arena = parent_arena
    register_class(parent)
    @arena = child_arena
    register_class(reference)
    register_class(concrete)
  end

  def __test_register_inherited_member_source_guard_fixture(
    parent_arena : Adamas::Compiler::Frontend::ArenaLike,
    parent_classes : Array(Adamas::Compiler::Frontend::ClassNode),
    child_arena : Adamas::Compiler::Frontend::ArenaLike,
    child_classes : Array(Adamas::Compiler::Frontend::ClassNode),
    child_modules : Array(Adamas::Compiler::Frontend::ModuleNode),
  ) : Nil
    @arena = parent_arena
    parent_classes.each { |node| register_class(node) }
    @arena = child_arena
    child_classes.each { |node| register_class(node) }
    child_modules.each { |node| register_module(node) }
  end

  def __test_drain_inherited_member_source_pending : Nil
    process_pending_lower_functions
  end

  def __test_inherited_member_source_binding_available?(
    target_name : String,
    source_name : String,
    selected_arg_types : Array(TypeRef),
    arg_count : Int32,
    has_block : Bool,
    has_named_args : Bool,
  ) : Bool
    selected = lookup_function_def_for_call(
      source_name, selected_arg_types.size, false, selected_arg_types,
    ) || raise "could not select registered source call #{source_name}"
    selected_name, source_def = selected
    source_arena = @function_def_arenas[selected_name]? || raise "missing selected source Arena #{selected_name}"
    !inherited_nilary_member_source_binding_for_target(
      target_name, selected_name, source_def, source_arena, arg_count, has_block, has_named_args,
    ).nil?
  end

  def __test_inherited_member_source_owner_registered?(owner_name : String) : Bool
    @class_info.has_key?(owner_name) || @module_defs.has_key?(owner_name)
  end

  def __test_inherited_member_source_def(name : String) : Adamas::Compiler::Frontend::DefNode
    @function_defs[name]? || raise "missing registered Def #{name}"
  end

  def __test_inherited_member_source_contract(
    parent_def : Adamas::Compiler::Frontend::DefNode,
    child_shadow_def : Adamas::Compiler::Frontend::DefNode,
    parent_arena : Adamas::Compiler::Frontend::ArenaLike,
    child_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : InheritedMemberSourceContractObservation
    lower_function_if_needed("ConcreteReference#observed")
    sibling_name = @function_defs.find do |registered_name, definition|
      registered_name != "ConcreteReference#value" &&
        definition.same?(child_shadow_def) && registered_name.includes?("$arity1")
    end.try(&.[0])
    sibling_def = sibling_name.try { |name| @function_defs[name]? }

    lower_function_if_needed("ConcreteReference#one_argument")
    # The first lower of `observed` can stop after requesting its nilary target.
    # Drain the pending work, then refresh the body and target before asserting
    # Def/Arena return stamps; an intermediate absent body is not a failure.
    process_pending_lower_functions

    observed = @module.function_by_name("ConcreteReference#observed") ||
               raise "missing lowered nilary member consumer"
    nilary_call = observed.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?("ConcreteReference#value") && call.args.empty? }
    target_name = nilary_call.try(&.method_name)
    target = target_name.try { |name| @module.function_by_name(name) }

    one_argument = @module.function_by_name("ConcreteReference#one_argument") ||
                   raise "missing lowered one-argument member consumer"
    one_arg_call = one_argument.blocks.flat_map(&.instructions)
      .compact_map(&.as?(Adamas::HIR::Call))
      .find { |call| call.method_name.starts_with?("ConcreteReference#value") && call.args.size == 1 }
    sibling_function = one_arg_call.try { |call| @module.function_by_name(call.method_name) }

    InheritedMemberSourceContractObservation.new(
      target_name,
      nilary_call.try(&.args.size) || -1,
      nilary_call.try(&.type),
      target_name.try { |name| @function_defs[name]?.try(&.same?(parent_def)) == true } || false,
      target_name.try { |name| @function_def_arenas[name]?.try(&.same?(parent_arena)) == true } || false,
      target.try(&.source_return_definition_id) == parent_def.object_id.to_u64,
      target.try(&.source_return_arena_key) == arena_map_key(parent_arena),
      @function_defs["Object#value"]?.try(&.same?(parent_def)) == true &&
        @function_def_arenas["Object#value"]?.try(&.same?(parent_arena)) == true,
      sibling_name != nil && sibling_def.try(&.same?(child_shadow_def)) == true &&
        @function_def_arenas[sibling_name.not_nil!]?.try(&.same?(child_arena)) == true,
      sibling_function.try(&.return_type),
      one_arg_call.try(&.method_name),
      one_arg_call.try(&.args.size) || -1,
      one_arg_call.try(&.type),
    )
  end

  def __test_inherited_member_source_receipt_staleness(
    parent_def : Adamas::Compiler::Frontend::DefNode,
    child_shadow_def : Adamas::Compiler::Frontend::DefNode,
    parent_arena : Adamas::Compiler::Frontend::ArenaLike,
    child_arena : Adamas::Compiler::Frontend::ArenaLike,
  ) : InheritedMemberSourceReceiptObservation
    target_name = "ConcreteReference#value"
    source_name = "Object#value"
    receipt = inherited_nilary_member_source_binding_for_target(
      target_name, source_name, parent_def, parent_arena, 0, false, false,
    ) || raise "could not capture inherited nilary source receipt"
    receipt_was_current = force_lower_exact_source_matches?(target_name, receipt)

    source_def = @function_defs[source_name]? || raise "missing lexical source Def"
    source_arena = @function_def_arenas[source_name]? || raise "missing lexical source Arena"
    physical_def = @function_defs[target_name]? || raise "missing physical shadow Def"
    physical_arena = @function_def_arenas[target_name]? || raise "missing physical shadow Arena"
    stale_source_def_rejected = false
    stale_source_arena_rejected = false
    crossed_physical_pair_rejected = false

    begin
      @function_defs[source_name] = child_shadow_def
      stale_source_def_rejected = !force_lower_exact_source_matches?(target_name, receipt)
      @function_defs[source_name] = source_def

      @function_def_arenas[source_name] = child_arena
      stale_source_arena_rejected = !force_lower_exact_source_matches?(target_name, receipt)
      @function_def_arenas[source_name] = source_arena

      @function_def_arenas[target_name] = parent_arena
      crossed_physical_pair_rejected = !force_lower_exact_source_matches?(target_name, receipt)
    ensure
      @function_defs[source_name] = source_def
      @function_def_arenas[source_name] = source_arena
      @function_defs[target_name] = physical_def
      @function_def_arenas[target_name] = physical_arena
    end

    same_complete = ForceLowerExactSourceBinding.new(
      parent_def, parent_arena, source_name, true, target_name,
      physical_def, physical_arena,
    )
    crossed_pair = ForceLowerExactSourceBinding.new(
      parent_def, parent_arena, source_name, true, target_name,
      physical_def, parent_arena,
    )
    same_absent = ForceLowerExactSourceBinding.new(
      parent_def, parent_arena, source_name, true, target_name,
    )
    one_sided_def = ForceLowerExactSourceBinding.new(
      parent_def, parent_arena, source_name, true, target_name,
      physical_def, nil,
    )
    one_sided_arena = ForceLowerExactSourceBinding.new(
      parent_def, parent_arena, source_name, true, target_name,
      nil, physical_arena,
    )

    InheritedMemberSourceReceiptObservation.new(
      receipt_was_current,
      stale_source_def_rejected,
      stale_source_arena_rejected,
      crossed_physical_pair_rejected,
      same_force_lower_exact_source_binding?(same_complete, same_complete),
      same_force_lower_exact_source_binding?(same_absent, same_absent),
      !same_force_lower_exact_source_binding?(one_sided_def, same_complete),
      !same_force_lower_exact_source_binding?(one_sided_arena, same_complete),
      !same_force_lower_exact_source_binding?(one_sided_def, one_sided_def),
      !same_force_lower_exact_source_binding?(one_sided_arena, one_sided_arena),
      !same_force_lower_exact_source_binding?(same_complete, crossed_pair),
    )
  end
end

private def inherited_member_source_contract_fixture
  parent_source = <<-CRYSTAL
    class Object
      def value : UInt64
        value(7_u64)
      end
    end
  CRYSTAL
  child_source = <<-CRYSTAL
    class Reference < Object
    end

    class ConcreteReference < Reference
      def value(item)
        item
      end

      def observed : UInt64
        self.value
      end

      def one_argument : Int32
        self.value(7_i32)
      end
    end
  CRYSTAL

  parent_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(parent_source),
  )
  parent_program = parent_parser.parse_program
  parent_parser.diagnostics.should be_empty
  parent_arena = parent_program.arena
  parent = parent_program.roots.compact_map do |root|
    parent_arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end.first? || raise "missing Object declaration"

  child_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(child_source),
  )
  child_program = child_parser.parse_program
  child_parser.diagnostics.should be_empty
  child_arena = child_program.arena
  child_classes = child_program.roots.compact_map do |root|
    child_arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end
  reference = child_classes.find { |node| String.new(node.name) == "Reference" } ||
              raise "missing Reference declaration"
  concrete = child_classes.find { |node| String.new(node.name) == "ConcreteReference" } ||
             raise "missing ConcreteReference declaration"

  converter = Adamas::HIR::AstToHir.new(
    child_arena,
    sources_by_arena: {
      parent_arena.object_id.to_u64 => parent_source,
      child_arena.object_id.to_u64 => child_source,
    },
  )
  converter.no_prelude = true
  converter.__test_register_inherited_member_source_classes(
    parent, parent_arena, reference, concrete, child_arena,
  )
  parent_def = converter.__test_inherited_member_source_def("Object#value")
  child_shadow_def = converter.__test_inherited_member_source_def("ConcreteReference#value")
  {converter, parent_arena, child_arena, parent_def, child_shadow_def}
end

private def inherited_member_source_guard_fixture
  parent_source = <<-CRYSTAL
    class Object
      def value : UInt64
        value(7_u64)
      end

      def requires(item : Int32) : Int32
        item
      end
    end

    class OtherProvider
      def value : UInt64
        9_u64
      end
    end

    abstract class AbstractProvider < Object
      abstract def abstract_value : UInt64
    end
  CRYSTAL
  child_source = <<-CRYSTAL
    class Reference < Object
    end

    class ConcreteReference < Reference
      def value(item)
        item
      end

      def requires(item : Int32) : Int32
        item
      end
    end

    abstract class AbstractReceiver < Reference
      def value(item)
        item
      end
    end

    class PolymorphicReceiver < Object
      def value(item)
        item
      end
    end

    class PolymorphicReceiverChild < PolymorphicReceiver
    end

    class AbstractProviderChild < AbstractProvider
      def abstract_value : UInt64
        11_u64
      end
    end

    module ModuleReceiver
      def value(item)
        item
      end
    end
  CRYSTAL

  parent_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(parent_source),
  )
  parent_program = parent_parser.parse_program
  parent_parser.diagnostics.should be_empty
  parent_arena = parent_program.arena
  parent_classes = parent_program.roots.compact_map do |root|
    parent_arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end

  child_parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(child_source),
  )
  child_program = child_parser.parse_program
  child_parser.diagnostics.should be_empty
  child_arena = child_program.arena
  child_classes = child_program.roots.compact_map do |root|
    child_arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
  end
  child_modules = child_program.roots.compact_map do |root|
    child_arena[root].as?(Adamas::Compiler::Frontend::ModuleNode)
  end

  converter = Adamas::HIR::AstToHir.new(
    child_arena,
    sources_by_arena: {
      parent_arena.object_id.to_u64 => parent_source,
      child_arena.object_id.to_u64 => child_source,
    },
  )
  converter.no_prelude = true
  converter.__test_register_inherited_member_source_guard_fixture(
    parent_arena, parent_classes, child_arena, child_classes, child_modules,
  )
  converter
end

describe "inherited nilary member source receipt contract" do
  it "re-owns only the concrete nilary body while retaining lexical and arity identities" do
    converter, parent_arena, child_arena, parent_def, child_shadow_def = inherited_member_source_contract_fixture
    parent_arena.object_id.should_not eq(child_arena.object_id)
    result = converter.__test_inherited_member_source_contract(
      parent_def, child_shadow_def, parent_arena, child_arena,
    )

    result.nilary_call_name.should eq("ConcreteReference#value")
    result.nilary_call_arg_count.should eq(0)
    result.nilary_call_type.should eq(Adamas::HIR::TypeRef::UINT64)
    result.nilary_target_source_def.should be_true
    result.nilary_target_source_arena.should be_true
    result.nilary_target_return_def_stamp.should be_true
    result.nilary_target_return_arena_stamp.should be_true
    result.source_registry_preserved.should be_true
    result.child_arity_sibling_preserved.should be_true
    result.child_sibling_return.should eq(Adamas::HIR::TypeRef::INT32)

    result.one_arg_call_name.should_not be_nil
    result.one_arg_call_name.not_nil!.should start_with("ConcreteReference#value")
    result.one_arg_call_name.not_nil!.should_not start_with("Object#value")
    result.one_arg_call_arg_count.should eq(1)
    result.one_arg_call_type.should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "rejects stale lexical Def/Arena and crossed physical witnesses before replay" do
    converter, parent_arena, child_arena, parent_def, child_shadow_def = inherited_member_source_contract_fixture
    result = converter.__test_inherited_member_source_receipt_staleness(
      parent_def, child_shadow_def, parent_arena, child_arena,
    )

    result.receipt_was_current.should be_true
    result.stale_source_def_rejected.should be_true
    result.stale_source_arena_rejected.should be_true
    result.crossed_physical_pair_rejected.should be_true
    result.same_complete_pair_equal.should be_true
    result.both_absent_pair_equal.should be_true
    result.one_sided_def_rejected.should be_true
    result.one_sided_arena_rejected.should be_true
    result.one_sided_def_self_rejected.should be_true
    result.one_sided_arena_self_rejected.should be_true
    result.crossed_pair_rejected.should be_true
  end

  it "rejects call shapes and receiver/source contexts outside the exact inherited nilary case" do
    converter = inherited_member_source_guard_fixture
    ["Object", "OtherProvider", "AbstractProvider"].each do |owner|
      converter.__test_inherited_member_source_owner_registered?(owner).should be_true
    end
    ["ConcreteReference", "AbstractReceiver", "PolymorphicReceiver",
     "PolymorphicReceiverChild", "AbstractProviderChild"].each do |owner|
      converter.__test_inherited_member_source_owner_registered?(owner).should be_true
    end
    converter.__test_inherited_member_source_owner_registered?("ModuleReceiver").should be_true

    # Every source name below resolves to the actual Def and Arena registered
    # from one of the parsed fixture programs. The guard method raises if any
    # source entry is missing, so these cases cannot pass on forged witnesses.
    no_args = [] of Adamas::HIR::TypeRef
    one_int_arg = [Adamas::HIR::TypeRef::INT32]
    cases = [
      {"ConcreteReference#value", "Object#value", no_args, 0, true, false},
      {"ConcreteReference#value", "Object#value", no_args, 0, false, true},
      {"ConcreteReference#requires", "Object#requires", one_int_arg, 1, false, false},
      {"ConcreteReference#value", "OtherProvider#value", no_args, 0, false, false},
      {"AbstractProviderChild#abstract_value", "AbstractProvider#abstract_value", no_args, 0, false, false},
      {"ModuleReceiver#value", "Object#value", no_args, 0, false, false},
      {"AbstractReceiver#value", "Object#value", no_args, 0, false, false},
      {"PolymorphicReceiver#value", "Object#value", no_args, 0, false, false},
    ]
    cases.each do |target, source, selected_arg_types, arg_count, has_block, has_named_args|
      converter.__test_inherited_member_source_binding_available?(
        target, source, selected_arg_types, arg_count, has_block, has_named_args,
      ).should be_false
    end
  end
end
