require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/hir/source_block_result_pattern"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_source_block_result_pattern(
    output : String,
    actual : String,
    owner : String?,
    formals : Array(String) = [] of String,
    bindings : Hash(String, String) = {} of String => String,
    actual_type_literal : Bool = false,
  ) : Tuple(String, TypeRef?, Bool)
    old_class = @current_class
    old_namespace = @current_namespace_override
    @current_class = owner
    @current_namespace_override = owner
    begin
      pattern = build_source_block_result_pattern(output, owner, formals, bindings)
      actual_type = canonical_bound_type_ref(actual)
      {
        pattern.restriction_name,
        pattern.type_ref,
        source_block_result_pattern_matches_value?(actual_type, actual_type_literal, pattern),
      }
    ensure
      @current_class = old_class
      @current_namespace_override = old_namespace
    end
  end
end

private def source_block_result_pattern_fixture
  source = <<-CRYSTAL
    class Path
    end

    module Scope
      class Path
      end

      class PathChild < Path
      end

      abstract class AbstractPath
      end

      class AbstractPathChild < AbstractPath
      end

      class Owner
      end

      class GenericOwner(T)
      end

      class Box(T)
      end

      class ChildBox(T) < Box(T)
      end

      class OtherBox(T)
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena)
  converter.seed_top_level_type_names(["Path", "Scope"])
  program.roots.each do |expression|
    case node = program.arena[expression]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end
  converter
end

describe "source block result patterns" do
  it "retains a tuple field's metaclass alternatives through structural matching" do
    converter = source_block_result_pattern_fixture
    _, _, accepted = converter.__test_source_block_result_pattern(
      "Tuple(Path.class | Int32, Bool)", "Tuple(Scope::Path.class | Int32, Bool)", "Scope::Owner",
    )
    _, _, rejected = converter.__test_source_block_result_pattern(
      "Tuple(Path, Bool)", "Tuple(Scope::Path.class | Scope::Path, Bool)", "Scope::Owner",
    )
    accepted.should be_true
    rejected.should be_false
  end

  it "retains a named tuple field's metaclass alternatives" do
    converter = source_block_result_pattern_fixture
    _, _, accepted = converter.__test_source_block_result_pattern(
      "NamedTuple(item: Path.class | Int32)", "NamedTuple(item: Scope::Path.class | Int32)", "Scope::Owner",
    )
    _, _, rejected = converter.__test_source_block_result_pattern(
      "NamedTuple(item: Path)", "NamedTuple(item: Scope::Path.class | Scope::Path)", "Scope::Owner",
    )
    accepted.should be_true
    rejected.should be_false
  end

  it "retains mixed source value kinds in nested Proc input and result slots" do
    converter = source_block_result_pattern_fixture
    ["Proc(Path.class | Int32, Bool)", "Proc(Bool, Path.class | Int32)"].each do |restriction|
      actual = restriction.gsub("Path", "Scope::Path")
      _, _, accepted = converter.__test_source_block_result_pattern(restriction, actual, "Scope::Owner")
      accepted.should be_true
    end
    _, _, rejected = converter.__test_source_block_result_pattern(
      "Proc(Bool, Path)", "Proc(Bool, Scope::Path.class | Scope::Path)", "Scope::Owner",
    )
    rejected.should be_false
  end

  it "admits metaclass values under Class without admitting instances" do
    converter = source_block_result_pattern_fixture
    _, _, accepts_class = converter.__test_source_block_result_pattern(
      "Class", "Scope::Path", "Scope::Owner", actual_type_literal: true,
    )
    _, _, rejects_instance = converter.__test_source_block_result_pattern(
      "Class", "Scope::Path", "Scope::Owner",
    )
    accepts_class.should be_true
    rejects_instance.should be_false
  end

  it "binds a bare output-only forall from the callback result" do
    converter = source_block_result_pattern_fixture
    restriction, concrete_type, matches = converter.__test_source_block_result_pattern(
      "T", "Int32", "Scope::Owner", ["T"],
    )
    restriction.should eq("T")
    concrete_type.should be_nil
    matches.should be_true
  end

  it "matches a nullable output-only forall against the non-Nil remainder" do
    converter = source_block_result_pattern_fixture
    _, _, matches = converter.__test_source_block_result_pattern(
      "T?", "Int32 | Nil", "Scope::Owner", ["T"],
    )
    matches.should be_true

    _, _, nil_only_matches = converter.__test_source_block_result_pattern(
      "T?", "Nil", "Scope::Owner", ["T"],
    )
    nil_only_matches.should be_true
  end

  it "matches top-level mixed union arms by the returned value kind" do
    converter = source_block_result_pattern_fixture
    output = "Path | ::Path.class"
    no_formals = [] of String
    no_bindings = {} of String => String

    _, _, accepts_instance_arm = converter.__test_source_block_result_pattern(
      output, "Scope::Path", "Scope::Owner", no_formals, no_bindings, false,
    )
    _, _, accepts_class_literal_arm = converter.__test_source_block_result_pattern(
      output, "::Path", "Scope::Owner", no_formals, no_bindings, true,
    )
    _, _, rejects_instance_as_class_literal = converter.__test_source_block_result_pattern(
      output, "Scope::Path", "Scope::Owner", no_formals, no_bindings, true,
    )
    _, _, rejects_class_literal_as_instance = converter.__test_source_block_result_pattern(
      output, "::Path", "Scope::Owner", no_formals, no_bindings, false,
    )

    accepts_instance_arm.should be_true
    accepts_class_literal_arm.should be_true
    rejects_instance_as_class_literal.should be_false
    rejects_class_literal_as_instance.should be_false
  end

  it "lets an unbound top-level formal infer either value kind" do
    converter = source_block_result_pattern_fixture
    no_bindings = {} of String => String
    _, _, accepts_instance = converter.__test_source_block_result_pattern(
      "T", "Scope::Path", "Scope::Owner", ["T"], no_bindings, false,
    )
    _, _, accepts_class_literal = converter.__test_source_block_result_pattern(
      "T", "Scope::Path", "Scope::Owner", ["T"], no_bindings, true,
    )

    accepts_instance.should be_true
    accepts_class_literal.should be_true
  end

  it "keeps a source-bound forall constrained to its resolved owner type" do
    converter = source_block_result_pattern_fixture
    _, _, accepts_subclass = converter.__test_source_block_result_pattern(
      "T", "Scope::PathChild", "Scope::Owner", ["T"], {"T" => "Path"},
    )
    _, _, rejects_shadowed_top_level_type = converter.__test_source_block_result_pattern(
      "T", "::Path", "Scope::Owner", ["T"], {"T" => "Path"},
    )
    accepts_subclass.should be_true
    rejects_shadowed_top_level_type.should be_false
  end

  it "keeps source-bound abstract numeric domains separate from their HIR carriers" do
    converter = source_block_result_pattern_fixture
    _, _, accepts_unsigned = converter.__test_source_block_result_pattern(
      "T", "UInt64", "Scope::Owner", ["T"], {"T" => "Int"},
    )
    _, _, rejects_float = converter.__test_source_block_result_pattern(
      "T", "Float64", "Scope::Owner", ["T"], {"T" => "Int"},
    )
    accepts_unsigned.should be_true
    rejects_float.should be_false
  end

  it "substitutes owner generic bindings without treating them as method formals" do
    converter = source_block_result_pattern_fixture
    _, concrete_type, accepts_owner_binding = converter.__test_source_block_result_pattern(
      "T", "Int32", "Scope::GenericOwner(Int32)", [] of String,
    )
    concrete_type.should eq(Adamas::HIR::TypeRef::INT32)
    accepts_owner_binding.should be_true

    _, _, rejects_owner_binding_mismatch = converter.__test_source_block_result_pattern(
      "T", "String", "Scope::GenericOwner(Int32)", [] of String,
    )
    rejects_owner_binding_mismatch.should be_false
  end

  it "resolves concrete names under the declaration owner" do
    converter = source_block_result_pattern_fixture
    _, _, accepts_nested = converter.__test_source_block_result_pattern(
      "Path", "Scope::Path", "Scope::Owner",
    )
    _, _, rejects_top_level = converter.__test_source_block_result_pattern(
      "Path", "::Path", "Scope::Owner",
    )
    accepts_nested.should be_true
    rejects_top_level.should be_false
  end

  it "requires the declared generic head and accepts its specialized ancestor" do
    converter = source_block_result_pattern_fixture
    _, _, accepts_exact = converter.__test_source_block_result_pattern(
      "Box(T)", "Scope::Box(Int32)", "Scope::Owner", ["T"],
    )
    _, _, accepts_projection = converter.__test_source_block_result_pattern(
      "Box(T)", "Scope::ChildBox(Int32)", "Scope::Owner", ["T"],
    )
    _, _, rejects_other_head = converter.__test_source_block_result_pattern(
      "Box(T)", "Scope::OtherBox(Int32)", "Scope::Owner", ["T"],
    )
    accepts_exact.should be_true
    accepts_projection.should be_true
    rejects_other_head.should be_false
  end

  it "matches each generic argument against a source-bound union restriction" do
    converter = source_block_result_pattern_fixture
    _, _, accepts_distributed_union = converter.__test_source_block_result_pattern(
      "Box(T)", "Scope::Box(Int32) | Scope::Box(String)", "Scope::Owner", ["T"],
      {"T" => "Int32 | String"},
    )
    _, _, accepts_whole_union = converter.__test_source_block_result_pattern(
      "Box(T)", "Scope::Box(Int32 | String)", "Scope::Owner", ["T"],
      {"T" => "Int32 | String"},
    )
    _, _, accepts_unbound_formal = converter.__test_source_block_result_pattern(
      "Box(T)", "Scope::Box(Int32)", "Scope::Owner", ["T"],
    )
    accepts_distributed_union.should be_true
    accepts_whole_union.should be_true
    accepts_unbound_formal.should be_true
  end

  it "applies bound union restrictions to distributed Array result arms" do
    converter = source_block_result_pattern_fixture
    _, _, accepts_distributed_union = converter.__test_source_block_result_pattern(
      "Array(T)", "Array(Int32) | Array(String)", "Scope::Owner", ["T"],
      {"T" => "Int32 | String"},
    )
    _, _, accepts_whole_union = converter.__test_source_block_result_pattern(
      "Array(T)", "Array(Int32 | String)", "Scope::Owner", ["T"],
      {"T" => "Int32 | String"},
    )
    _, _, accepts_unbound_formal = converter.__test_source_block_result_pattern(
      "Array(T)", "Array(Int32)", "Scope::Owner", ["T"],
    )
    _, _, rejects_wrong_union_arm = converter.__test_source_block_result_pattern(
      "Array(T)", "Array(Int32) | Array(Float64)", "Scope::Owner", ["T"],
      {"T" => "Int32 | String"},
    )
    _, _, rejects_distributed_concrete_argument = converter.__test_source_block_result_pattern(
      "Array(Int32)", "Array(Int32) | Array(String)", "Scope::Owner",
    )
    accepts_distributed_union.should be_true
    accepts_whole_union.should be_true
    accepts_unbound_formal.should be_true
    rejects_wrong_union_arm.should be_false
    rejects_distributed_concrete_argument.should be_false
  end

  it "keeps concrete generic arguments invariant while preserving abstract domains" do
    converter = source_block_result_pattern_fixture
    _, _, rejects_concrete_subclass_arg = converter.__test_source_block_result_pattern(
      "Box(Path)", "Scope::Box(Scope::PathChild)", "Scope::Owner",
    )
    _, _, accepts_abstract_nominal_arg = converter.__test_source_block_result_pattern(
      "Box(AbstractPath)", "Scope::Box(Scope::AbstractPathChild)", "Scope::Owner",
    )
    _, _, accepts_abstract_numeric_domain = converter.__test_source_block_result_pattern(
      "Box(Int)", "Scope::Box(UInt64)", "Scope::Owner",
    )
    _, _, rejects_numeric_carrier_mismatch = converter.__test_source_block_result_pattern(
      "Box(Int32)", "Scope::Box(UInt64)", "Scope::Owner",
    )
    rejects_concrete_subclass_arg.should be_false
    accepts_abstract_nominal_arg.should be_true
    accepts_abstract_numeric_domain.should be_true
    rejects_numeric_carrier_mismatch.should be_false
  end

  it "requires repeated tuple formals to bind the same actual type" do
    converter = source_block_result_pattern_fixture
    _, _, accepts_same = converter.__test_source_block_result_pattern(
      "Tuple(T, T)", "Tuple(Int32, Int32)", "Scope::Owner", ["T"],
    )
    _, _, rejects_mixed = converter.__test_source_block_result_pattern(
      "Tuple(T, T)", "Tuple(Int32, String)", "Scope::Owner", ["T"],
    )
    accepts_same.should be_true
    rejects_mixed.should be_false
  end

  it "keeps distinct method formals independently bound" do
    converter = source_block_result_pattern_fixture
    _, _, matches = converter.__test_source_block_result_pattern(
      "Tuple(T, U)", "Tuple(Int32, String)", "Scope::Owner", ["T", "U"],
    )
    matches.should be_true
  end

  it "matches Void in a nested Proc result slot while keeping top-level Void separate" do
    converter = source_block_result_pattern_fixture
    _, _, accepts_proc = converter.__test_source_block_result_pattern(
      "Proc(Int32, Void)", "Proc(Int32, Void)", "Scope::Owner",
    )
    _, _, rejects_top_level_void = converter.__test_source_block_result_pattern(
      "Void", "Void", "Scope::Owner",
    )
    accepts_proc.should be_true
    rejects_top_level_void.should be_false
  end

  it "applies Crystal's Proc discarded and bottom result rules" do
    converter = source_block_result_pattern_fixture
    _, _, nil_discards_string_result = converter.__test_source_block_result_pattern(
      "Proc(Int32, Nil)", "Proc(Int32, String)", "Scope::Owner",
    )
    _, _, void_discards_string_result = converter.__test_source_block_result_pattern(
      "Proc(Int32, Void)", "Proc(Int32, String)", "Scope::Owner",
    )
    _, _, no_return_satisfies_result = converter.__test_source_block_result_pattern(
      "Proc(Int32, String)", "Proc(Int32, NoReturn)", "Scope::Owner",
    )
    _, _, nil_discards_no_return_result = converter.__test_source_block_result_pattern(
      "Proc(Int32, Nil)", "Proc(Int32, NoReturn)", "Scope::Owner",
    )
    _, _, rejects_proc_input_mismatch = converter.__test_source_block_result_pattern(
      "Proc(Int32, String)", "Proc(String, String)", "Scope::Owner",
    )
    nil_discards_string_result.should be_true
    nil_discards_no_return_result.should be_true
    void_discards_string_result.should be_true
    no_return_satisfies_result.should be_true
    rejects_proc_input_mismatch.should be_false
  end

  it "does not accept Proc result adaptation inside invariant or tuple slots" do
    converter = source_block_result_pattern_fixture
    _, _, rejects_nested_adaptation = converter.__test_source_block_result_pattern(
      "Box(Proc(Int32, Nil))", "Scope::Box(Proc(Int32, String))", "Scope::Owner",
    )
    _, _, accepts_exact_nested_result = converter.__test_source_block_result_pattern(
      "Box(Proc(Int32, Nil))", "Scope::Box(Proc(Int32, Nil))", "Scope::Owner",
    )
    _, _, rejects_tuple_nested_adaptation = converter.__test_source_block_result_pattern(
      "Box(Tuple(Proc(Int32, Nil)))", "Scope::Box(Tuple(Proc(Int32, String)))", "Scope::Owner",
    )
    _, _, accepts_exact_tuple_result = converter.__test_source_block_result_pattern(
      "Box(Tuple(Proc(Int32, Nil)))", "Scope::Box(Tuple(Proc(Int32, Nil)))", "Scope::Owner",
    )
    _, _, accepts_nested_no_return = converter.__test_source_block_result_pattern(
      "Box(Proc(Int32, String))", "Scope::Box(Proc(Int32, NoReturn))", "Scope::Owner",
    )
    _, _, rejects_nested_nil_adaptation_from_no_return = converter.__test_source_block_result_pattern(
      "Box(Proc(Int32, Nil))", "Scope::Box(Proc(Int32, NoReturn))", "Scope::Owner",
    )
    _, _, accepts_named_tuple_field_adaptation = converter.__test_source_block_result_pattern(
      "Box(NamedTuple(callback: Proc(Int32, Nil)))",
      "Scope::Box(NamedTuple(callback: Proc(Int32, String)))", "Scope::Owner",
    )
    rejects_nested_adaptation.should be_false
    accepts_exact_nested_result.should be_true
    rejects_tuple_nested_adaptation.should be_false
    accepts_exact_tuple_result.should be_true
    accepts_nested_no_return.should be_true
    rejects_nested_nil_adaptation_from_no_return.should be_false
    accepts_named_tuple_field_adaptation.should be_true
  end

  it "requires an exact NamedTuple key set while allowing field Proc Nil adaptation" do
    converter = source_block_result_pattern_fixture
    _, _, accepts_reordered_exact_keys = converter.__test_source_block_result_pattern(
      "NamedTuple(extra: Int32, callback: Proc(Int32, Nil))",
      "NamedTuple(callback: Proc(Int32, String), extra: Int32)", "Scope::Owner",
    )
    _, _, rejects_extra_key_with_nil_adaptation = converter.__test_source_block_result_pattern(
      "NamedTuple(callback: Proc(Int32, Nil))",
      "NamedTuple(callback: Proc(Int32, String), extra: Int32)", "Scope::Owner",
    )
    _, _, rejects_missing_key = converter.__test_source_block_result_pattern(
      "NamedTuple(callback: Proc(Int32, Nil), extra: Int32)",
      "NamedTuple(callback: Proc(Int32, String))", "Scope::Owner",
    )

    accepts_reordered_exact_keys.should be_true
    rejects_extra_key_with_nil_adaptation.should be_false
    rejects_missing_key.should be_false
  end

  it "fails closed when a concrete leaf cannot be resolved" do
    converter = source_block_result_pattern_fixture
    _, concrete_type, matches = converter.__test_source_block_result_pattern(
      "MissingSourceType", "String", "Scope::Owner",
    )
    concrete_type.should be_nil
    matches.should be_false
  end
end
