require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_source_generic_shape_match(actual : String, restriction : String)
    source_generic_restriction_match?(actual, restriction)
  end

  def __test_source_rejection_handoff(def_node, actual : String?, cached : Bool = false, direct : Bool = false, alternative = nil)
    base_name = "GenericAdmissionCases#source_rejection_probe"
    entry_name = "#{base_name}$first"
    set_function_def_entry(entry_name, def_node)
    set_function_def_entry("#{base_name}$second", alternative) if alternative
    actual_type = actual ? type_ref_for_name(actual) : TypeRef::VOID
    input = CallResolutionInput.new(
      func_name: direct ? entry_name : base_name,
      arg_count: 1,
      arg_types: [actual_type],
      has_block: false,
      has_splat: false,
      has_named: false,
      named_names: nil,
    )
    @call_resolution_memo.clear
    @call_resolution_memo_enabled = true
    @call_resolution_memo_hits = 0_i64
    2.times { resolve_call_target(input) } if cached
    rejections = [] of Tuple(String, String)
    target = resolve_call_target(input, rejections)
    {target.try(&.symbol_name), rejections, @call_resolution_memo_hits}
  end

  def __test_builtin_generic_admission(def_node, actual : String)
    actual_type = type_ref_for_name(actual)
    restriction_name = function_param_infos(def_node).first.type_annotation.not_nil!
    {
      params_compatible_with_args?(def_node, [actual_type], "GenericAdmissionCases"),
      declared_type_match_score(actual_type, restriction_name),
    }
  end

  def __test_bound_generic_admission(def_node, actual : String)
    with_isolated_type_param_map({"S" => "Nil"}) do
      actual_type = type_ref_for_name(actual)
      restriction_name = function_param_infos(def_node).first.type_annotation.not_nil!
      normalized = normalize_declared_type_name(restriction_name, "AdmissionBound(Nil)", specialize_bare_generics: false)
      {
        params_compatible_with_args?(def_node, [actual_type], "AdmissionBound(Nil)"),
        declared_type_match_score(actual_type, normalized),
      }
    end
  end
end

private def generic_admission_fixture
  source = <<-CRYSTAL
    alias AdmissionInt = Int
    class AdmissionAnimal
    end
    class AdmissionCat < AdmissionAnimal
    end
    module AdmissionView
    end
    module AdmissionRelay
      include AdmissionView
    end
    module AdmissionAppliedView(T)
    end
    module AdmissionAppliedRelay(T)
      include AdmissionAppliedView(T)
    end
    module AdmissionOther
      module AdmissionView
      end
    end
    class AdmissionDirect
      include AdmissionView
    end
    class AdmissionIndirect
      include AdmissionRelay
    end
    class AdmissionInherited < AdmissionDirect
    end
    class AdmissionApplied
      include AdmissionAppliedView(Int32)
    end
    class AdmissionAppliedIndirect
      include AdmissionAppliedRelay(Int32)
    end
    class AdmissionWrongNamespace
      include AdmissionOther::AdmissionView
    end
    class AdmissionBox(T)
    end
    class AdmissionContext(T)
    end
    class AdmissionState
    end
    class AdmissionBound(S)
      def bare_context(value : AdmissionContext); end
      def bound_context(value : AdmissionContext(S)); end
    end
    class GenericAdmissionCases
      def concrete_array(value : Array(Int32)); end
      def string_array(value : Array(String)); end
      def concrete_hash(value : Hash(String, Int32)); end
      def nested_array(value : Array(Array(Int32))); end
      def abstract_array(value : Array(Int)); end
      def alias_array(value : Array(AdmissionInt)); end
      def c_array(value : Array(LibC::Int)); end
      def parent_array(value : Array(AdmissionAnimal)); end
      def module_array(value : Array(AdmissionView)); end
      def applied_module_array(value : Array(AdmissionAppliedView(Int32))); end
      def object_array(value : Array(Object)); end
      def nil_proc(value : Proc(Nil)); end
      def nested_nil_proc(value : Array(Proc(Nil))); end
      def proc_argument(value : Proc(Int32, Nil)); end
      def bare_array(value : Array); end
      def concrete_box(value : AdmissionBox(Int32)); end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source})
  # Mirror the CLI's top-level census before lexical normalization.
  top_level_names = [] of String
  parsed.roots.each do |root|
    case node = parsed.arena[root]
    when Adamas::Compiler::Frontend::ClassNode,
         Adamas::Compiler::Frontend::ModuleNode,
         Adamas::Compiler::Frontend::AliasNode
      top_level_names << String.new(node.name)
    end
  end
  converter.seed_top_level_type_names(top_level_names)
  definitions = {} of String => Adamas::Compiler::Frontend::DefNode
  parsed.roots.each do |root|
    node = parsed.arena[root]
    if node.is_a?(Adamas::Compiler::Frontend::AliasNode)
      converter.register_alias(node)
      next
    end
    if node.is_a?(Adamas::Compiler::Frontend::ModuleNode)
      converter.register_module(node)
      next
    end
    owner = node.as(Adamas::Compiler::Frontend::ClassNode)
    converter.register_class(owner)
    owner.body.try &.each do |member|
      if definition = parsed.arena[member].as?(Adamas::Compiler::Frontend::DefNode)
        definitions[String.new(definition.name)] = definition
      end
    end
  end
  {converter, definitions}
end

describe "source restrictions of generic arguments" do
  it "defers erased actual arguments instead of certifying a contradiction" do
    converter, _definitions = generic_admission_fixture
    {
      {"Array", "Array(Int32)"},
      {"Pointer", "Pointer(Int32)"},
      {"Proc", "Proc(Int32)"},
      {"AdmissionBox", "AdmissionBox(Int32)"},
    }.each do |actual, restriction|
      converter.__test_source_generic_shape_match(actual, restriction).should be_nil
    end
  end

  {
    {"concrete_array", "Array(UInt64)"},
    {"string_array", "Array(Int32)"},
    {"concrete_hash", "Hash(String, UInt64)"},
    {"nested_array", "Array(Array(UInt64))"},
    {"concrete_box", "AdmissionBox(UInt64)"},
    {"c_array", "Array(UInt64)"},
    {"proc_argument", "Proc(String, Int32)"},
    {"module_array", "Array(AdmissionWrongNamespace)"},
    {"module_array", "Array(AdmissionAnimal)"},
    {"applied_module_array", "Array(AdmissionAppliedView(UInt64))"},
  }.each do |method, actual|
    it "rejects #{actual} in #{method} at admission and ranking" do
      converter, definitions = generic_admission_fixture
      compatible, score = converter.__test_builtin_generic_admission(definitions[method], actual)
      compatible.should be_false
      score.should be_nil
    end
  end

  {
    {"concrete_array", "Array(Int32)"},
    {"concrete_hash", "Hash(String, Int32)"},
    {"nested_array", "Array(Array(Int32))"},
    {"abstract_array", "Array(UInt64)"},
    {"alias_array", "Array(UInt64)"},
    {"parent_array", "Array(AdmissionCat)"},
    {"module_array", "Array(AdmissionDirect)"},
    {"module_array", "Array(AdmissionIndirect)"},
    {"module_array", "Array(AdmissionInherited)"},
    {"applied_module_array", "Array(AdmissionApplied)"},
    {"applied_module_array", "Array(AdmissionAppliedIndirect)"},
    {"bare_array", "Array(UInt64)"},
    {"object_array", "Array(Int32)"},
    {"nil_proc", "Proc(Int32)"},
    {"nested_nil_proc", "Array(Proc(Int32))"},
    {"proc_argument", "Proc(Int32, Int32)"},
  }.each do |method, actual|
    it "admits #{actual} in #{method} using the declared restriction" do
      converter, definitions = generic_admission_fixture
      compatible, score = converter.__test_builtin_generic_admission(definitions[method], actual)
      compatible.should be_true
      score.should_not be_nil
    end
  end

  it "keeps a bare generic restriction broad inside a bound generic owner" do
    converter, definitions = generic_admission_fixture
    compatible, score = converter.__test_bound_generic_admission(definitions["bare_context"], "AdmissionContext(AdmissionState | Nil)")
    compatible.should be_true
    score.should_not be_nil
  end

  it "rejects a different specialization of an applied restriction in a bound owner" do
    converter, definitions = generic_admission_fixture
    compatible, score = converter.__test_bound_generic_admission(definitions["bound_context"], "AdmissionContext(AdmissionState | Nil)")
    compatible.should be_false
    score.should be_nil
  end
end


describe "source generic rejection handoff" do
  it "retains a proven mismatch while query lookup still returns no target" do
    converter, definitions = generic_admission_fixture
    target, rejections, _ = converter.__test_source_rejection_handoff(definitions["concrete_array"], "Array(UInt64)")
    target.should be_nil
    rejections.should eq([{"Array(UInt64)", "Array(Int32)"}])
  end

  it "recovers rejection evidence after a memoized lookup miss" do
    converter, definitions = generic_admission_fixture
    target, rejections, memo_hits = converter.__test_source_rejection_handoff(definitions["concrete_array"], "Array(UInt64)", cached: true)
    target.should be_nil
    rejections.should eq([{"Array(UInt64)", "Array(Int32)"}])
    memo_hits.should be > 0
  end

  it "checks a preselected serialized target against known source arguments" do
    converter, definitions = generic_admission_fixture
    target, rejections, _ = converter.__test_source_rejection_handoff(definitions["concrete_array"], "Array(UInt64)", direct: true)
    target.should be_nil
    rejections.should eq([{"Array(UInt64)", "Array(Int32)"}])
  end

  it "does not turn an unknown argument into a known rejection" do
    converter, definitions = generic_admission_fixture
    target, rejections, _ = converter.__test_source_rejection_handoff(definitions["concrete_array"], nil)
    target.should_not be_nil
    rejections.should be_empty
  end

  it "preserves a compatible alternative after rejecting another overload" do
    converter, definitions = generic_admission_fixture
    target, rejections, _ = converter.__test_source_rejection_handoff(
      definitions["concrete_array"], "Array(UInt64)", alternative: definitions["abstract_array"],
    )
    target.should eq("GenericAdmissionCases#source_rejection_probe$second")
    rejections.should be_empty
  end
end


# Union(A, B) is the internal spelling produced by generic argument binding.
# Every possible runtime member must satisfy a parameter restriction.
describe "generic restriction admission for union arguments" do
  {
    "AdmissionContext(Nil) | AdmissionContext(AdmissionState)",
    "Union(AdmissionContext(Nil), AdmissionContext(AdmissionState))",
  }.each do |actual|
    it "admits every specialization of a bare generic in #{actual}" do
      converter, definitions = generic_admission_fixture
      converter.__test_source_generic_shape_match(actual, "AdmissionContext").should be_true
      compatible, score = converter.__test_bound_generic_admission(definitions["bare_context"], actual)
      compatible.should be_true
      score.should_not be_nil
    end

    it "rejects a nonmatching member of an applied restriction in #{actual}" do
      converter, definitions = generic_admission_fixture
      converter.__test_source_generic_shape_match(actual, "AdmissionContext(Nil)").should be_false
      compatible, score = converter.__test_bound_generic_admission(definitions["bound_context"], actual)
      compatible.should be_false
      score.should be_nil
    end
  end

  {
    "Union(AdmissionContext(Nil), AdmissionAnimal)",
    "Union(AdmissionContext(Nil), Nil)",
    "Union(AdmissionContext(Nil), AdmissionOther::AdmissionContext(Nil))",
  }.each do |actual|
    it "rejects a union containing a different nominal family in #{actual}" do
      converter, definitions = generic_admission_fixture
      converter.__test_source_generic_shape_match(actual, "AdmissionContext").should be_false
      compatible, score = converter.__test_bound_generic_admission(definitions["bare_context"], actual)
      compatible.should be_false
      score.should be_nil
    end
  end
end


describe "nullable union restriction equivalence" do
  it "admits canonical generic union members for a nullable restriction" do
    converter, _ = generic_admission_fixture
    converter.__test_source_generic_shape_match("Nil | AdmissionContext(Nil)", "AdmissionContext(Nil)?").should be_true
    converter.__test_source_generic_shape_match("Union(AdmissionContext(Nil), Nil)", "AdmissionContext(Nil)?").should be_true
    converter.__test_source_generic_shape_match("AdmissionContext(Nil)?", "AdmissionContext(Nil) | Nil").should be_true
  end

  it "rejects a nullable generic restriction when an actual member is outside its family" do
    converter, _ = generic_admission_fixture
    converter.__test_source_generic_shape_match("AdmissionContext(Nil) | AdmissionState", "AdmissionContext(Nil)?").should be_false
  end

  it "leaves nongeneric deferred unions to ordinary TypeRef admission" do
    converter, _ = generic_admission_fixture
    converter.__test_source_generic_shape_match("Nil | Object", "Bool?").should be_nil
    converter.__test_source_generic_shape_match("Nil | AdmissionAnimal", "AdmissionAnimal?").should be_nil
  end
end


class Adamas::HIR::AstToHir
  def __test_exact_generic_union_runtime_type(actual : String, restriction : String)
    should_use_exact_call_type_for_local_inference?(type_ref_for_name(restriction), type_ref_for_name(actual))
  end
end

describe "bare generic union runtime specialization" do
  it "keeps all admitted applied variants in the runtime parameter" do
    converter, _ = generic_admission_fixture
    converter.__test_exact_generic_union_runtime_type("AdmissionContext(Nil) | AdmissionContext(AdmissionState)", "AdmissionContext").should be_true
  end

  it "does not specialize an unrelated union member under the generic restriction" do
    converter, _ = generic_admission_fixture
    converter.__test_exact_generic_union_runtime_type("AdmissionContext(Nil) | AdmissionAnimal", "AdmissionContext").should be_false
  end

  it "does not specialize a nullable actual under a nonnullable generic restriction" do
    converter, _ = generic_admission_fixture
    converter.__test_exact_generic_union_runtime_type("AdmissionContext(Nil)?", "AdmissionContext").should be_false
  end
end
