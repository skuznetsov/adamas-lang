require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_type_name(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end
end

private def named_hash_parse(
  source : String,
) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  result = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  ).parse_program
  {result.arena, result.roots}
end

private def lower_named_hash_program(
  source : String,
  function_name : String,
) : {Adamas::HIR::AstToHir, Adamas::HIR::Function}
  arena, roots = named_hash_parse(source)
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.arena = arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  defs = [] of Adamas::Compiler::Frontend::DefNode
  roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      defs << node
    end
  end

  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  classes.each { |node| converter.lower_class(node) }
  target = defs.find { |node| String.new(node.name) == function_name }
  raise "function #{function_name} not found" unless target
  {converter, converter.lower_def(target)}
end

describe "named hash collection literals" do
  it "captures complex entries in source order, constructs once, applies every setter, and returns the container" do
    converter, function = lower_named_hash_program(<<-CRYSTAL, "build_named_hash")
      class NamedHashProbe
        def initialize
        end

        def []=(key : String, value : String) : String
          "setter-result"
        end
      end

      def named_hash_key(label : String) : String
        label
      end

      def named_hash_value(label : String) : String
        label
      end

      def build_named_hash : NamedHashProbe
        NamedHashProbe{
          named_hash_key("same") => named_hash_value("first"),
          named_hash_key("same") => named_hash_value("last"),
        }
      end
    CRYSTAL

    calls = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
    names = calls.map(&.method_name)

    key_calls = names.each_index.select { |index| names[index].includes?("named_hash_key") }.to_a
    value_calls = names.each_index.select { |index| names[index].includes?("named_hash_value") }.to_a
    constructor_calls = names.each_index.select { |index| names[index].includes?("NamedHashProbe.new") }.to_a
    setter_calls = names.each_index.select { |index| names[index].includes?("NamedHashProbe#[]=") }.to_a

    key_calls.size.should eq(2)
    value_calls.size.should eq(2)
    constructor_calls.size.should eq(1)
    setter_calls.size.should eq(2)
    key_calls[0].should be < value_calls[0]
    value_calls[0].should be < key_calls[1]
    key_calls[1].should be < value_calls[1]
    value_calls[1].should be < constructor_calls[0]
    constructor_calls[0].should be < setter_calls[0]
    setter_calls[0].should be < setter_calls[1]

    converter.__test_type_name(function.return_type).should eq("NamedHashProbe")
  end

  it "keeps constructor mutation visible to a directly referenced local at setter time" do
    _, function = lower_named_hash_program(<<-CRYSTAL, "build_mutated_source")
      class NamedHashMutationProbe
        @@before_new : Proc(Nil)? = nil

        def self.before_new=(callback : Proc(Nil))
          @@before_new = callback
        end

        def initialize
          @@before_new.not_nil!.call
        end

        def []=(key : String, value : String) : Nil
        end
      end

      def build_mutated_source
        source = "before"
        NamedHashMutationProbe.before_new = -> { source = "after" }
        NamedHashMutationProbe{"key" => source}
      end
    CRYSTAL

    calls = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
    setter = calls.find { |call| call.method_name.includes?("NamedHashMutationProbe#[]=") }
    setter.should_not be_nil
    calls.any? { |call| call.method_name.includes?("NamedHashMutationProbe.new") }.should be_true
  end

  it "preserves separately inferred key and value parameters for a bare generic receiver" do
    _, function = lower_named_hash_program(<<-CRYSTAL, "inferred_hash")
      class Hash(K, V)
        def self.new
        end

        def []=(key : K, value : V) : V
          value
        end
      end

      def inferred_hash
        Hash{"key" => 42}
      end
    CRYSTAL

    calls = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
    calls.any? { |call| call.method_name.includes?("Hash(String, Int32).new") }.should be_true
    calls.any? { |call| call.method_name.includes?("Hash(String, Int32)#[]=") }.should be_true
  end

  it "keeps an explicit generic receiver and lowers a typed empty literal through new" do
    _, non_empty = lower_named_hash_program(<<-CRYSTAL, "explicit_hash")
      class Hash(K, V)
        def self.new
        end

        def []=(key : K, value : V) : V
          value
        end
      end

      def explicit_hash
        Hash(String, Int32){"key" => 42}
      end
    CRYSTAL
    non_empty_calls = non_empty.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
    non_empty_calls.any? { |call| call.method_name.includes?("Hash(String, Int32).new") }.should be_true

    _, empty = lower_named_hash_program(<<-CRYSTAL, "empty_hash")
      class Hash(K, V)
        def self.new
        end
      end

      def empty_hash
        Hash(String, Int32){} of String => Int32
      end
    CRYSTAL
    empty_calls = empty.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
    empty_calls.any? { |call| call.method_name.includes?("Hash(String, Int32).new") }.should be_true
    empty_calls.any? { |call| call.method_name.includes?("Hash(String, Int32)#[]=") }.should be_false
  end
end
