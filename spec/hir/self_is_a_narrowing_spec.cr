require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_self_is_a_fixture(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  main = [] of UInt64
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
      converter.register_class(node)
    else
      main << root.index.to_u64
    end
  end
  classes.each { |node| converter.lower_class(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

private def self_guard_fixture : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class SelfGuardBase
      def guarded : Bool
        self.is_a?(SelfGuardChild) && self.child_only
      end
      def guarded_if : Bool
        if self.is_a?(SelfGuardChild)
          self.child_only
        else
          false
        end
      end
      def keep_self : SelfGuardBase
        self.is_a?(SelfGuardChild) && self.child_only
        self
      end
    end
    class SelfGuardChild < SelfGuardBase
      def child_only : Bool
        true
      end
    end
    class SelfMetaGuardBase
      def self.guarded : Bool
        self.is_a?(SelfMetaGuardChild.class) && self.class_only
      end
      def self.guarded_if : Bool
        if self.is_a?(SelfMetaGuardChild.class)
          self.class_only
        else
          false
        end
      end
      def self.keep_self
        self.is_a?(SelfMetaGuardChild.class) && self.class_only
        self
      end
    end
    class SelfMetaGuardChild < SelfMetaGuardBase
      def self.class_only : Bool
        true
      end
    end
    class SelfMetaAliasBase
      alias TargetMeta = SelfMetaAliasChild.class
      def self.guarded_alias : Bool
        self.is_a?(TargetMeta) && self.class_only
      end
      def self.guarded_if_alias : Bool
        if self.is_a?(TargetMeta)
          self.class_only
        else
          false
        end
      end
      def self.class_only : Bool
        false
      end
    end
    class SelfMetaAliasChild < SelfMetaAliasBase
      def self.class_only : Bool
        true
      end
    end
    SelfMetaAliasBase.guarded_alias
    SelfMetaAliasChild.guarded_alias
    SelfMetaAliasBase.guarded_if_alias
    SelfMetaAliasChild.guarded_if_alias
    SelfGuardBase.new.guarded
    SelfGuardBase.new.guarded_if
    SelfGuardBase.new.keep_self
    SelfMetaGuardBase.guarded
    SelfMetaGuardChild.guarded
    SelfMetaGuardBase.guarded_if
    SelfMetaGuardChild.guarded_if
    SelfMetaGuardBase.keep_self
  CRYSTAL
  lower_self_is_a_fixture(source)
end

private def self_meta_instance_member_rejected : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class SelfMetaNegativeBase
      def self.guarded : Bool
        self.is_a?(SelfMetaNegativeChild.class) && self.instance_only
      end
    end
    class SelfMetaNegativeChild < SelfMetaNegativeBase
      def instance_only : Bool
        true
      end
    end
    SelfMetaNegativeChild.guarded
  CRYSTAL
  lower_self_is_a_fixture(source)
end

describe "self is_a? source narrowing" do
  it "resolves RHS and if-body calls through the proven self type" do
    converter = self_guard_fixture
    {"guarded", "guarded_if"}.each do |method|
      function = converter.module.functions.find { |fn| fn.name == "SelfGuardBase##{method}" }.not_nil!
      calls = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
        .select { |call| call.method_name.includes?("child_only") }
      calls.should_not be_empty
      calls.each { |call| call.method_name.should contain("SelfGuardChild#child_only") }
    end
  end

  it "restores the original self binding after the short-circuit RHS" do
    converter = self_guard_fixture
    function = converter.module.functions.find { |fn| fn.name == "SelfGuardBase#keep_self" }.not_nil!
    returns = function.blocks.compact_map { |block| block.terminator.as?(Adamas::HIR::Return) }
    returns.should_not be_empty
    returns.each { |ret| ret.value.should eq(function.params.first.id) }
  end

  it "keeps class-literal kind while narrowing class-method self" do
    converter = self_guard_fixture
    {"guarded", "guarded_if"}.each do |method|
      function = converter.module.functions.find { |fn| fn.name == "SelfMetaGuardChild.#{method}" }.not_nil!
      calls = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
        .select { |call| call.method_name.includes?("class_only") }
      calls.should_not be_empty
      calls.each { |call| call.method_name.should contain("SelfMetaGuardChild.class_only") }
    end
  end

  it "uses exact class-object self identity without changing instance is_a? checks" do
    converter = self_guard_fixture
    {"SelfMetaGuardBase.guarded", "SelfMetaGuardBase.guarded_if",
     "SelfMetaAliasBase.guarded_alias", "SelfMetaAliasBase.guarded_if_alias"}.each do |name|
      function = converter.module.functions.find { |fn| fn.name == name }.not_nil!
      function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::IsA)).should be_empty
    end

    instance_function = converter.module.functions.find { |fn| fn.name == "SelfGuardBase#guarded" }.not_nil!
    instance_checks = instance_function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::IsA))
    instance_checks.should_not be_empty
  end

  it "resolves a class-literal alias when narrowing class-method self" do
    converter = self_guard_fixture
    {"guarded_alias", "guarded_if_alias"}.each do |method|
      function = converter.module.functions.find { |fn| fn.name == "SelfMetaAliasChild.#{method}" }.not_nil!
      calls = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
        .select { |call| call.method_name.includes?("class_only") }
      calls.should_not be_empty
      calls.each { |call| call.method_name.should contain("SelfMetaAliasChild.class_only") }
    end
  end

  it "restores the original class-method self binding after the guard" do
    converter = self_guard_fixture
    function = converter.module.functions.find { |fn| fn.name == "SelfMetaGuardBase.keep_self" }.not_nil!
    self_type = converter.class_info["SelfMetaGuardBase"].type_ref
    original_self = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Literal))
      .find { |literal| literal.type == self_type && literal.value.is_a?(Nil) }.not_nil!.id
    returns = function.blocks.compact_map { |block| block.terminator.as?(Adamas::HIR::Return) }
    returns.should_not be_empty
    returns.each { |ret| ret.value.should eq(original_self) }
  end

  it "does not let a class-literal narrowing resolve an instance-only child method" do
    converter = self_meta_instance_member_rejected
    function = converter.module.functions.find { |fn| fn.name == "SelfMetaNegativeChild.guarded" }.not_nil!
    converter.module.has_function_with_body?(function.name).should be_true
    calls = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.includes?("instance_only") }
    calls.should_not be_empty
    calls.each do |call|
      call.method_name.should eq("SelfMetaNegativeChild.instance_only")
      call.receiver_value.should eq(Adamas::HIR::Call::NO_RECEIVER)
    end
    instance_target = converter.module.functions.find do |fn|
      fn.name == "SelfMetaNegativeChild#instance_only" ||
        fn.name.starts_with?("SelfMetaNegativeChild#instance_only$")
    end.not_nil!
    converter.module.has_function_with_body?(instance_target.name).should be_true
    converter.module.has_function_with_body?("SelfMetaNegativeChild.instance_only").should be_false
  end
end
