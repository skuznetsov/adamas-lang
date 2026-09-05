require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_absolute_pointer_null_program(source : String) : Adamas::HIR::AstToHir
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena

  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode

  result.roots.each do |expr_id|
    node = result.arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    end
  end

  enum_nodes.each { |node| converter.register_enum(node) }
  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter
end

private def absolute_pointer_instructions(function : Adamas::HIR::Function) : Array(Adamas::HIR::Value)
  function.blocks.flat_map(&.instructions)
end

private def zero_pointer_casts(
  converter : Adamas::HIR::AstToHir,
  function : Adamas::HIR::Function,
) : Array(Adamas::HIR::Cast)
  instructions = absolute_pointer_instructions(function)
  casts = instructions.compact_map(&.as?(Adamas::HIR::Cast)).select do |candidate|
    descriptor = converter.module.get_type_descriptor(candidate.type)
    next false unless descriptor && descriptor.name == "Pointer(Probe)"
    value = instructions.find { |instruction| instruction.id == candidate.value }
    value.is_a?(Adamas::HIR::Literal) && value.value == 0_i64
  end
  casts
end

private def assert_zero_pointer_cast(
  converter : Adamas::HIR::AstToHir,
  function : Adamas::HIR::Function,
) : Adamas::HIR::Cast
  instructions = absolute_pointer_instructions(function)
  cast = zero_pointer_casts(converter, function).first?
  cast.should_not be_nil

  cast_value = instructions.find { |instruction| instruction.id == cast.not_nil!.value }
  cast_value.should_not be_nil
  literal = cast_value.not_nil!.as(Adamas::HIR::Literal)
  literal.value.should eq(0_i64)

  instructions.any? do |instruction|
    instruction.as?(Adamas::HIR::Call).try do |call|
      call.method_name.includes?("Pointer(Probe).null")
    end || false
  end.should be_false

  cast.not_nil!
end

describe "absolute Pointer(T).null lowering" do
  it "emits a typed zero cast for direct relative and root-qualified calls" do
    converter = lower_absolute_pointer_null_program(<<-CRYSTAL)
      struct Probe
        def relative_null : Pointer(self)
          Pointer(self).null
        end

        def absolute_null : ::Pointer(self)
          ::Pointer(self).null
        end

        def relative_null_call : Pointer(self)
          Pointer(self).null()
        end

        def absolute_null_call : ::Pointer(self)
          ::Pointer(self).null()
        end
      end
    CRYSTAL

    relative = converter.module.functions.find { |function| function.name.includes?("Probe#relative_null") }
    absolute = converter.module.functions.find { |function| function.name.includes?("Probe#absolute_null") }
    relative_call = converter.module.functions.find { |function| function.name.includes?("Probe#relative_null_call") }
    absolute_call = converter.module.functions.find { |function| function.name.includes?("Probe#absolute_null_call") }
    relative.should_not be_nil
    absolute.should_not be_nil
    relative_call.should_not be_nil
    absolute_call.should_not be_nil

    relative_cast = assert_zero_pointer_cast(converter, relative.not_nil!)
    absolute_cast = assert_zero_pointer_cast(converter, absolute.not_nil!)
    relative_call_cast = assert_zero_pointer_cast(converter, relative_call.not_nil!)
    absolute_call_cast = assert_zero_pointer_cast(converter, absolute_call.not_nil!)

    absolute_cast.type.should eq(relative_cast.type)
    relative_call_cast.type.should eq(relative_cast.type)
    absolute_call_cast.type.should eq(relative_cast.type)
  end

  it "lowers root-qualified Pointer(self).null defaults through the intrinsic" do
    converter = lower_absolute_pointer_null_program(<<-CRYSTAL)
      struct Probe
        property previous : ::Pointer(self) = ::Pointer(self).null
        property next : ::Pointer(self) = ::Pointer(self).null()
        property marker : ::Pointer(self) = ::Pointer(self).new(1_u64)
      end
    CRYSTAL

    allocator = converter.module.functions.find { |function| function.name.starts_with?("Probe.new") }
    allocator.should_not be_nil
    casts = zero_pointer_casts(converter, allocator.not_nil!)
    casts.size.should eq(2)
    casts.each { |cast| cast.type.should eq(casts.first.type) }
    assert_zero_pointer_cast(converter, allocator.not_nil!)
  end

  it "keeps user-namespaced Pointer(T).null forms as ordinary calls" do
    converter = lower_absolute_pointer_null_program(<<-CRYSTAL)
      struct Probe
      end

      module User
        struct Pointer(T)
          def self.null : UInt64
            7_u64
          end
        end
      end

      def user_pointer_null : UInt64
        ::User::Pointer(Probe).null
      end

      def user_pointer_null_call : UInt64
        ::User::Pointer(Probe).null()
      end
    CRYSTAL

    {"user_pointer_null", "user_pointer_null_call"}.each do |name|
      function = converter.module.functions.find { |candidate| candidate.name == name }
      function.should_not be_nil
      instructions = absolute_pointer_instructions(function.not_nil!)
      calls = instructions.compact_map(&.as?(Adamas::HIR::Call))
      calls.any? { |call| call.method_name.includes?("User::Pointer") }.should be_true
      instructions.compact_map(&.as?(Adamas::HIR::Cast)).any? do |cast|
        converter.module.get_type_descriptor(cast.type).try(&.name) == "Pointer(Probe)"
      end.should be_false
    end
  end
end
