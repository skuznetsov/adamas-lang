require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_enum_predicate_member_value(enum_name : String, member_name : String) : Int64?
    enum_member_value(enum_name, member_name)
  end

  def __test_enum_source_family(owner : String, method_name : String) : Bool
    qualified_source_method_family_exists?(owner, method_name, '#')
  end

  def __test_enum_inferred_signature(owner : String, method_name : String) : Nil
    set_function_type_entry("#{owner}##{method_name}", TypeRef::BOOL, true)
  end
end

private def enum_predicate_source_fixture(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena, sources_by_arena: {arena.object_id.to_u64 => source}
  )
  converter.no_prelude = true
  main_exprs = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::EnumNode
      converter.register_enum(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    when Adamas::Compiler::Frontend::AnnotationNode
      # Enum annotations are sibling roots and are read from source while the
      # enum itself is registered; they are not executable main expressions.
    else
      main_exprs << root_id.index.to_u64
    end
  end
  program.roots.each do |root_id|
    node = arena[root_id]
    converter.lower_def(node) if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  converter.lower_main(main_exprs) unless main_exprs.empty?
  converter.flush_pending_functions
  converter
end

private def enum_predicate_source_function(
  converter : Adamas::HIR::AstToHir,
  prefix : String,
) : Adamas::HIR::Function
  converter.module.functions.find do |function|
    function.name.starts_with?(prefix) && !function.blocks.empty?
  end.not_nil!
end

private def enum_predicate_source_ops(function : Adamas::HIR::Function) : Array(Adamas::HIR::BinaryOp)
  function.blocks.flat_map(&.instructions).compact_map do |instruction|
    instruction.as?(Adamas::HIR::BinaryOperation).try(&.op)
  end
end

private def enum_predicate_source_calls(function : Adamas::HIR::Function) : Array(Adamas::HIR::Call)
  function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
end

describe "source enum predicate ownership and flags semantics" do
  it "recognizes rooted Flags for implicit member numbering" do
    source = <<-CRYSTAL
      @[::Flags]
      enum RootedImplicitFlags : UInt8
        First
        Second
      end

      enum PlainImplicitValues : UInt8
        First
        Second
      end
    CRYSTAL
    converter = enum_predicate_source_fixture(source)

    converter.__test_enum_predicate_member_value("RootedImplicitFlags", "First").should eq(1_i64)
    converter.__test_enum_predicate_member_value("RootedImplicitFlags", "Second").should eq(2_i64)
    converter.__test_enum_predicate_member_value("PlainImplicitValues", "First").should eq(0_i64)
    converter.__test_enum_predicate_member_value("PlainImplicitValues", "Second").should eq(1_i64)
  end

  it "lowers bare and explicit Flags predicates as bit membership" do
    converter = enum_predicate_source_fixture(<<-CRYSTAL)
      @[::Flags]
      enum SourcePredicateFlags : UInt8
        Read = 1
        Write = 2
        Execute = 4

        def implicit_read_check : Bool
          read?
        end

        def explicit_write_check : Bool
          self.write?
        end

        def explicit_paren_read_check : Bool
          read?()
        end
      end

      enum SourcePredicateColor : UInt8
        Red = 1
        Blue = 2

        def implicit_red_check : Bool
          red?
        end

        def explicit_blue_check : Bool
          self.blue?
        end
      end

      def flags_implicit(value : SourcePredicateFlags) : Bool
        value.implicit_read_check
      end

      def flags_explicit(value : SourcePredicateFlags) : Bool
        value.explicit_write_check
      end

      def flags_explicit_paren(value : SourcePredicateFlags) : Bool
        value.explicit_paren_read_check
      end

      def color_implicit(value : SourcePredicateColor) : Bool
        value.implicit_red_check
      end

      def color_explicit(value : SourcePredicateColor) : Bool
        value.explicit_blue_check
      end

      flags_implicit(SourcePredicateFlags::Read)
      flags_explicit(SourcePredicateFlags::Write)
      flags_explicit_paren(SourcePredicateFlags::Read)
      color_implicit(SourcePredicateColor::Red)
      color_explicit(SourcePredicateColor::Blue)
    CRYSTAL

    flags_implicit = enum_predicate_source_function(converter, "SourcePredicateFlags#implicit_read_check")
    enum_predicate_source_ops(flags_implicit).should contain(Adamas::HIR::BinaryOp::BitAnd)
    enum_predicate_source_ops(flags_implicit).should contain(Adamas::HIR::BinaryOp::Eq)

    flags_explicit = enum_predicate_source_function(converter, "SourcePredicateFlags#explicit_write_check")
    enum_predicate_source_ops(flags_explicit).should contain(Adamas::HIR::BinaryOp::BitAnd)
    enum_predicate_source_ops(flags_explicit).should contain(Adamas::HIR::BinaryOp::Eq)

    flags_explicit_paren = enum_predicate_source_function(converter, "SourcePredicateFlags#explicit_paren_read_check")
    enum_predicate_source_ops(flags_explicit_paren).should contain(Adamas::HIR::BinaryOp::BitAnd)
    enum_predicate_source_ops(flags_explicit_paren).should contain(Adamas::HIR::BinaryOp::Eq)

    color_implicit = enum_predicate_source_function(converter, "SourcePredicateColor#implicit_red_check")
    enum_predicate_source_ops(color_implicit).should contain(Adamas::HIR::BinaryOp::Eq)
    enum_predicate_source_ops(color_implicit).should_not contain(Adamas::HIR::BinaryOp::BitAnd)

    color_explicit = enum_predicate_source_function(converter, "SourcePredicateColor#explicit_blue_check")
    enum_predicate_source_ops(color_explicit).should contain(Adamas::HIR::BinaryOp::Eq)
    enum_predicate_source_ops(color_explicit).should_not contain(Adamas::HIR::BinaryOp::BitAnd)
  end

  it "does not treat an unknown explicit predicate as an enum member" do
    source = <<-CRYSTAL
      @[::Flags]
      enum UnknownPredicateFlags : UInt8
        Read = 1
      end

      def unknown_explicit(value : UnknownPredicateFlags) : Bool
        value.not_declared?
      end

      unknown_explicit(UnknownPredicateFlags::Read)
    CRYSTAL

    converter = enum_predicate_source_fixture(source)
    unknown = enum_predicate_source_function(converter, "unknown_explicit")
    unknown_call = enum_predicate_source_calls(unknown).find do |call|
      call.method_name.includes?("not_declared?")
    end
    unknown_call.should_not be_nil
    unknown_call.not_nil!.type.should eq(Adamas::HIR::TypeRef::VOID)
    enum_predicate_source_ops(unknown).should_not contain(Adamas::HIR::BinaryOp::BitAnd)
    enum_predicate_source_ops(unknown).should_not contain(Adamas::HIR::BinaryOp::Eq)
  end

  it "does not treat an unknown bare predicate as an enum member" do
    source = <<-CRYSTAL
      @[::Flags]
      enum UnknownBarePredicateFlags : UInt8
        Read = 1

        def unknown_bare : Bool
          not_declared?
        end
      end

      def trigger_unknown_bare(value : UnknownBarePredicateFlags) : Bool
        value.unknown_bare
      end

      trigger_unknown_bare(UnknownBarePredicateFlags::Read)
    CRYSTAL

    converter = enum_predicate_source_fixture(source)
    unknown = enum_predicate_source_function(converter, "UnknownBarePredicateFlags#unknown_bare")
    unknown_call = enum_predicate_source_calls(unknown).find do |call|
      call.method_name.includes?("not_declared?")
    end
    unknown_call.should_not be_nil
    unknown_call.not_nil!.type.should eq(Adamas::HIR::TypeRef::VOID)
    enum_predicate_source_ops(unknown).should_not contain(Adamas::HIR::BinaryOp::BitAnd)
    enum_predicate_source_ops(unknown).should_not contain(Adamas::HIR::BinaryOp::Eq)
  end
end


describe "enum source declarations versus inferred signatures" do
  it "keeps Flags auto constants separate from generated member predicates" do
    converter = enum_predicate_source_fixture(<<-CRYSTAL)
      @[::Flags]
      enum AutoFlags : Int16
        Read = 1
        Write = 2
      end

      enum PlainValues : Int16
        Red = 1
      end
    CRYSTAL
    converter.__test_enum_predicate_member_value("AutoFlags", "None").should eq(0_i64)
    converter.__test_enum_predicate_member_value("AutoFlags", "All").should eq(3_i64)
    converter.__test_enum_predicate_member_value("PlainValues", "None").should be_nil
    converter.__test_enum_predicate_member_value("PlainValues", "All").should be_nil
  end

  it "does not promote an inferred Bool result to a source declaration" do
    converter = enum_predicate_source_fixture(<<-CRYSTAL)
      enum PredicateAuthority : Int16
        Read = 1

        def custom? : Bool
          true
        end
      end
    CRYSTAL
    converter.__test_enum_inferred_signature("PredicateAuthority", "all?")
    converter.__test_enum_source_family("PredicateAuthority", "all?").should be_false
    converter.__test_enum_source_family("PredicateAuthority", "custom?").should be_true
  end

  it "preserves a user definition overriding a generated predicate" do
    converter = enum_predicate_source_fixture(<<-CRYSTAL)
      @[::Flags]
      enum OverrideFlags : Int16
        Read = 1
        Write = 2

        def read? : Bool
          false
        end

        def check_read : Bool
          read?
        end
      end

      def trigger_override(value : OverrideFlags) : Bool
        value.check_read
      end
      trigger_override(OverrideFlags::Read)
    CRYSTAL
    check = enum_predicate_source_function(converter, "OverrideFlags#check_read")
    enum_predicate_source_ops(check).should_not contain(Adamas::HIR::BinaryOp::BitAnd)
    enum_predicate_source_calls(check).any? { |call| call.method_name.includes?("read?") }.should be_true
  end
end


describe "enum constant admission" do
  it "rejects nonexistent constants instead of lowering zero" do
    ["All", "None", "Undeclared"].each do |name|
      expect_raises(Adamas::HIR::LoweringError, "undefined constant PlainConstantOwner::#{name}") do
        enum_predicate_source_fixture(<<-CRYSTAL)
          enum PlainConstantOwner
            Red = 1
          end
          PlainConstantOwner::#{name}
        CRYSTAL
      end
    end
    expect_raises(Adamas::HIR::LoweringError, "undefined constant FlagConstantOwner::Undeclared") do
      enum_predicate_source_fixture(<<-CRYSTAL)
        @[::Flags]
        enum FlagConstantOwner
          Read = 1
        end
        FlagConstantOwner::Undeclared
      CRYSTAL
    end
  end
end


describe "enum constant source spelling" do
  it "does not apply symbol normalization to constant names" do
    ["READ", "ALL"].each do |name|
      expect_raises(Adamas::HIR::LoweringError, "undefined constant ExactCaseFlags::#{name}") do
        enum_predicate_source_fixture(<<-CRYSTAL)
          @[::Flags]
          enum ExactCaseFlags
            Read = 1
          end
          ExactCaseFlags::#{name}
        CRYSTAL
      end
    end
  end
end
