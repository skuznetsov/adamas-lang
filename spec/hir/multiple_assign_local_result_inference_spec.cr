require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  # Inspect local assignment inference in a freshly registered method body,
  # before lowering can independently add tuple-index types.
  def __test_multiple_assign_local_result_type(
    owner_name : String,
    method_name : String,
    local_name : String,
    foreign_current_arena : Bool = false,
    overlapping_foreign_arena : Bool = false,
  ) : String?
    key = "#{owner_name}.#{method_name}"
    matches = @function_defs.select do |registered_name, _|
      registered_name == key || registered_name.starts_with?("#{key}$")
    end.values.uniq(&.object_id)
    raise "expected one registered method #{key}, got #{matches.size}" unless matches.size == 1

    definition = matches.first
    body = definition.body || raise "method #{key} has no body"

    @current_class = owner_name
    @current_method = method_name
    @current_method_is_class = true
    @current_def_node = definition
    @infer_self_type_name = owner_name
    @infer_body_context = body
    @current_typeof_locals = {} of String => Adamas::HIR::TypeRef
    @current_typeof_local_names = {} of String => String

    if foreign_current_arena || overlapping_foreign_arena
      foreign = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(overlapping_foreign_arena ? ("nil\n" * 400) : "nil"),
      ).parse_program
      @arena = foreign.arena
    end

    infer_local_type_from_body(body, local_name, owner_name).try do |type_ref|
      get_type_name_from_ref(type_ref)
    end
  end

  def __test_multiple_assign_local_arena_remap(
    owner_name : String,
    method_name : String,
    local_name : String,
    replacement_source : String,
  ) : {String?, String?}
    first = __test_multiple_assign_local_result_type(owner_name, method_name, local_name)
    key = "#{owner_name}.#{method_name}"
    registered_name, definition = @function_defs.find do |name, _|
      name == key || name.starts_with?("#{key}$")
    end || raise "missing registered method #{key}"
    replacement = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(replacement_source),
    ).parse_program
    raise "replacement must fit the registered definition" unless arena_fits_def?(replacement.arena, definition)

    set_function_def_arena(registered_name, replacement.arena)
    second = __test_multiple_assign_local_result_type(owner_name, method_name, local_name)
    {first, second}
  end
end

private def parse_multiple_assign_local_result_probe(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  parsed = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  converter = Adamas::HIR::AstToHir.new(
    parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  converter.arena = parsed.arena
  parsed.roots.each do |root_id|
    if node = parsed.arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end
  converter
end

private def multiple_assign_local_result_source : String
  <<-CRYSTAL
    class MultipleAssignLocalResultProbe
      def self.pair : Tuple(Int32, Int64)
        {65_i32, 66_i64}
      end

      def self.nullable_pair : Tuple(Int32 | Nil, Int64)
        {nil, 66_i64}
      end

      def self.yield_pair : Tuple(Int32, Int64)
        yield
      end

      def self.yield_pair_twice : Tuple(Int32, Int64)
        yield_pair { yield }
      end

      def self.bool_pair : Tuple(Bool, Int64)
        {true, 66_i64}
      end

      def self.with_number
        yield 7_i32
      end

      def self.literal_result
        first, second = {65_i32, 66_i64}
        first
      end

      def self.direct_helper_result
        first, second = pair
        first
      end

      def self.one_yield_result
        first, second = yield_pair { pair }
        first
      end

      def self.two_yield_result
        first, second = yield_pair_twice { pair }
        first
      end

      def self.nullable_helper_result
        first, second = nullable_pair
        first
      end

      def self.aliased_tuple_result
        tuple_value = pair
        first, second = tuple_value
        first
      end

      def self.partial_slot_result
        tuple_value : Tuple(Void, Int64)
        first, second = tuple_value
        second
      end

      def self.splat_result
        first, *rest = pair
        first
      end

      def self.shadowed_block_result
        first = 65_i32
        with_number do |first|
          first, second = bool_pair
        end
        first
      end

      def self.captured_block_result
        first = nil
        with_number do |ignored|
          first, second = pair
        end
        first
      end

      def self.nested_shadowed_block_result
        first = 65_i32
        with_number do |ignored|
          with_number do |first|
            first, second = bool_pair
          end
        end
        first
      end
    end
  CRYSTAL
end

describe "multiple-assignment local inference from call results" do
  {
    "literal_result"         => "Int32",
    "direct_helper_result"   => "Int32",
    "nullable_helper_result" => "Nil | Int32",
    "aliased_tuple_result"   => "Int32",
  }.each do |method_name, expected_type|
    it "projects the first slot of #{method_name}" do
      converter = parse_multiple_assign_local_result_probe(multiple_assign_local_result_source)
      converter.__test_multiple_assign_local_result_type(
        "MultipleAssignLocalResultProbe",
        method_name,
        "first",
      ).should eq(expected_type)
    end
  end

  it "preserves the second slot's distinct type" do
    converter = parse_multiple_assign_local_result_probe(multiple_assign_local_result_source)
    converter.__test_multiple_assign_local_result_type("MultipleAssignLocalResultProbe", "direct_helper_result", "second").should eq("Int64")
  end

  it "does not shift indices by filtering an unresolved slot" do
    converter = parse_multiple_assign_local_result_probe(multiple_assign_local_result_source)
    converter.__test_multiple_assign_local_result_type("MultipleAssignLocalResultProbe", "partial_slot_result", "first").should be_nil
    converter.__test_multiple_assign_local_result_type("MultipleAssignLocalResultProbe", "partial_slot_result", "second").should be_nil
  end

  it "does not guess positional slots for a splatted target list" do
    converter = parse_multiple_assign_local_result_probe(multiple_assign_local_result_source)
    converter.__test_multiple_assign_local_result_type("MultipleAssignLocalResultProbe", "splat_result", "first").should be_nil
  end

  it "keeps a shadowing block parameter separate from the outer local" do
    converter = parse_multiple_assign_local_result_probe(multiple_assign_local_result_source)
    converter.__test_multiple_assign_local_result_type("MultipleAssignLocalResultProbe", "shadowed_block_result", "first").should eq("Int32")
  end

  it "retains tuple-call writes to a captured outer local" do
    converter = parse_multiple_assign_local_result_probe(multiple_assign_local_result_source)
    converter.__test_multiple_assign_local_result_type("MultipleAssignLocalResultProbe", "captured_block_result", "first").should eq("Nil | Int32")
  end

  it "retains binding ownership across intermediate capturing blocks" do
    converter = parse_multiple_assign_local_result_probe(multiple_assign_local_result_source)
    converter.__test_multiple_assign_local_result_type("MultipleAssignLocalResultProbe", "nested_shadowed_block_result", "first").should eq("Int32")
  end

  it "discovers binding ownership in the arena that owns the source body" do
    converter = parse_multiple_assign_local_result_probe(multiple_assign_local_result_source)
    converter.__test_multiple_assign_local_result_type("MultipleAssignLocalResultProbe", "direct_helper_result", "first", foreign_current_arena: true).should eq("Int32")
  end

  it "uses registered body identity when a foreign arena has overlapping indices" do
    converter = parse_multiple_assign_local_result_probe(multiple_assign_local_result_source)
    converter.__test_multiple_assign_local_result_type("MultipleAssignLocalResultProbe", "direct_helper_result", "first", overlapping_foreign_arena: true).should eq("Int32")
  end

  it "does not reuse a local type after the body is explicitly remapped to another arena" do
    source = <<-CRYSTAL
      class MultipleAssignArenaRemapProbe
        def self.value
          local_value = 65_i32
          local_value
        end
      end
    CRYSTAL
    converter = parse_multiple_assign_local_result_probe(source)
    converter.__test_multiple_assign_local_arena_remap(
      "MultipleAssignArenaRemapProbe", "value", "local_value", source.gsub("65_i32", "65_i64"),
    ).should eq({"Int32", "Int64"})
  end
end
