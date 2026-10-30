require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_yield_result_selected_definition(
    name : String?,
    argument_annotation : String? = nil,
    alternate_arena : Adamas::Compiler::Frontend::ArenaLike? = nil,
  ) : Bool
    return selected_call_returns_yield_result?(nil) unless name
    definitions = @function_defs.select do |entry_name, definition|
      strip_type_suffix(entry_name) == name &&
        (!argument_annotation || function_param_infos(definition).first?.try(&.type_annotation) == argument_annotation)
    end.values.uniq(&.object_id)
    raise "expected one selected definition for #{name}, got #{definitions.size}" unless definitions.size == 1
    selected_call_returns_yield_result?(definitions.first, alternate_arena)
  end
end

private def yield_result_call_identity_fixture
  source = <<-CRYSTAL
    class YieldResultPhysicalOwner
      def initialize(first : Nil, second : Int32, third : Bool, &block : ->)
      end
    end
    class YieldResultOtherFactory
      def self.new(first : String, second : String, third : Nil, &block : -> Int32)
        yield
      end
    end
    class YieldResultOverloads
      def self.value(first : Int32, &)
        1
      end
      def self.value(first : String, &)
        yield
      end
      def new(&)
        yield
      end
      def self.new(&)
        1
      end
      def self.discard(&) : Nil
        yield
      end
      def self.generic(&block : -> T) : T forall T
        yield
      end
      def self.explicit_return(&)
        return yield
      end
      def self.delegate(&)
        new { yield }
      end
      def self.unless_return(flag : Bool, &)
        unless flag
          return 1
        end
        yield
      end
      def self.while_return(flag : Bool, &)
        while flag
          return 1
        end
        yield
      end
      def self.until_return(flag : Bool, &)
        until flag
          return 1
        end
        yield
      end
    end
    class YieldResultAlpha
      class Same
        def self.value(&)
          yield
        end
      end
    end
    class YieldResultBeta
      class Same
        def self.value(&)
          1
        end
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  parsed.roots.each do |root|
    converter.register_class(parsed.arena[root].as(Adamas::Compiler::Frontend::ClassNode))
  end
  converter
end

describe "selected yield result call identity" do
  it "does not borrow a factory when no source definition was selected" do
    yield_result_call_identity_fixture.__test_yield_result_selected_definition(nil).should be_false
  end

  it "does not classify an allocator through its initializer's block contract" do
    yield_result_call_identity_fixture.__test_yield_result_selected_definition("YieldResultPhysicalOwner#initialize").should be_false
  end

  it "retains an unannotated explicit factory's direct block result" do
    yield_result_call_identity_fixture.__test_yield_result_selected_definition("YieldResultOtherFactory.new").should be_true
  end

  it "classifies only the selected overload" do
    converter = yield_result_call_identity_fixture
    converter.__test_yield_result_selected_definition("YieldResultOverloads.value", "Int32").should be_false
    converter.__test_yield_result_selected_definition("YieldResultOverloads.value", "String").should be_true
  end

  it "keeps class and instance declarations distinct" do
    converter = yield_result_call_identity_fixture
    converter.__test_yield_result_selected_definition("YieldResultOverloads.new").should be_false
    converter.__test_yield_result_selected_definition("YieldResultOverloads#new").should be_true
  end

  it "keeps equal short owners in separate namespaces" do
    converter = yield_result_call_identity_fixture
    converter.__test_yield_result_selected_definition("YieldResultAlpha::Same.value").should be_true
    converter.__test_yield_result_selected_definition("YieldResultBeta::Same.value").should be_false
  end

  it "does not replace a declared Nil result with the callback result" do
    yield_result_call_identity_fixture.__test_yield_result_selected_definition("YieldResultOverloads.discard").should be_false
  end

  it "leaves a generic annotated result to source contract substitution" do
    yield_result_call_identity_fixture.__test_yield_result_selected_definition("YieldResultOverloads.generic").should be_false
  end

  it "accepts a source-local explicit return yield" do
    yield_result_call_identity_fixture.__test_yield_result_selected_definition("YieldResultOverloads.explicit_return").should be_true
  end

  it "does not certify delegated results through family aliases" do
    yield_result_call_identity_fixture.__test_yield_result_selected_definition("YieldResultOverloads.delegate").should be_false
  end

  it "does not erase an early return inside unless" do
    yield_result_call_identity_fixture.__test_yield_result_selected_definition("YieldResultOverloads.unless_return").should be_false
  end

  it "does not erase an early return inside while" do
    yield_result_call_identity_fixture.__test_yield_result_selected_definition("YieldResultOverloads.while_return").should be_false
  end

  it "does not erase an early return inside until" do
    yield_result_call_identity_fixture.__test_yield_result_selected_definition("YieldResultOverloads.until_return").should be_false
  end

  it "reads the selected declaration from its registered arena" do
    parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new("1\n2\n3"))
    foreign = parser.parse_program
    yield_result_call_identity_fixture.__test_yield_result_selected_definition(
      "YieldResultOtherFactory.new", alternate_arena: foreign.arena,
    ).should be_true
  end
end
