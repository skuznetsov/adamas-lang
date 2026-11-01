require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_raw_flag_condition_state(condition : String) : Int32
    evaluate_flag_condition_state(condition)
  end

  def __test_expand_raw_flag_text(text : String) : String?
    expand_flag_macro_text(text)
  end
end

private def raw_flag_converter(flags : Set(String)) : Adamas::HIR::AstToHir
  converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
  converter.compilation_flags = flags
  converter
end

describe "raw macro flag condition state" do
  it "preserves Crystal precedence for negated compound flags" do
    thread_condition = "!flag?(:without_mt) && !flag?(:preview_mt) || flag?(:execution_context)"

    raw_flag_converter(Set{"preview_mt", "execution_context"})
      .__test_raw_flag_condition_state(thread_condition).should eq(2)
    raw_flag_converter(Set{"preview_mt"})
      .__test_raw_flag_condition_state(thread_condition).should eq(1)
    raw_flag_converter(Set(String).new)
      .__test_raw_flag_condition_state(thread_condition).should eq(2)
    raw_flag_converter(Set{"without_mt", "preview_mt"})
      .__test_raw_flag_condition_state(thread_condition).should eq(1)
  end

  it "keeps true, false, and unknown distinct through short-circuit operators" do
    converter = raw_flag_converter(Set{"enabled"})

    converter.__test_raw_flag_condition_state("unresolved_condition").should eq(0)
    converter.__test_raw_flag_condition_state("flag?(:enabled) || unresolved_condition").should eq(2)
    converter.__test_raw_flag_condition_state("flag?(:disabled) && unresolved_condition").should eq(1)
    converter.__test_raw_flag_condition_state("unresolved_condition || flag?(:enabled)").should eq(0)
    converter.__test_raw_flag_condition_state("unresolved_condition && flag?(:disabled)").should eq(0)
    converter.__test_raw_flag_condition_state("unresolved_condition || flag?(:disabled)").should eq(0)
    converter.__test_raw_flag_condition_state("unresolved_condition && flag?(:enabled)").should eq(0)
  end

  it "defers branch selection when the left condition is unresolved" do
    converter = raw_flag_converter(Set{"enabled"})

    or_expanded = converter.__test_expand_raw_flag_text(<<-MACRO)
      {% if unresolved_condition || flag?(:enabled) %}
        selected
      {% else %}
        fallback
      {% end %}
      MACRO
    or_expanded.should be_nil

    and_expanded = converter.__test_expand_raw_flag_text(<<-MACRO)
      {% if unresolved_condition && flag?(:disabled) %}
        selected
      {% else %}
        fallback
      {% end %}
      MACRO
    and_expanded.should be_nil
  end

  it "does not split boolean operators inside quoted flag names" do
    converter = raw_flag_converter(Set{"quoted&&flag"})

    converter.__test_raw_flag_condition_state("flag?(\"quoted&&flag\")").should eq(2)
  end

  it "parses grouped conditions and compound unless as grouped negation" do
    converter = raw_flag_converter(Set{"right"})

    converter.__test_raw_flag_condition_state("!(flag?(:left) || flag?(:right))").should eq(1)
    converter.__test_raw_flag_condition_state("!((flag?(:left)) || flag?(:right))").should eq(1)

    expanded = converter.__test_expand_raw_flag_text(<<-MACRO)
      {% unless flag?(:left) || flag?(:right) %}
        wrong
      {% else %}
        selected
      {% end %}
      MACRO
    expanded.try(&.strip).should eq("selected")
  end

  it "selects elsif using the same true/false state contract" do
    source = <<-MACRO
      {% if !flag?(:without_mt) && !flag?(:preview_mt) || flag?(:execution_context) %}
        modern
      {% elsif flag?(:preview_mt) %}
        preview
      {% else %}
        fallback
      {% end %}
      MACRO

    legacy = raw_flag_converter(Set{"preview_mt"})
    legacy.__test_expand_raw_flag_text(source).try(&.strip).should eq("preview")

    modern = raw_flag_converter(Set{"preview_mt", "execution_context"})
    modern.__test_expand_raw_flag_text(source).try(&.strip).should eq("modern")
  end

  it "does not turn an unsupported condition into false" do
    converter = raw_flag_converter(Set(String).new)
    expanded = converter.__test_expand_raw_flag_text(<<-MACRO)
      {% if unresolved_condition %}
        selected
      {% else %}
        fallback
      {% end %}
      MACRO

    expanded.should be_nil
  end

  it "keeps false compare_versions results distinct from unsupported comparisons" do
    converter = raw_flag_converter(Set(String).new)

    converter.__test_raw_flag_condition_state("compare_versions(\"1.0.0\", \"2.0.0\") < 0").should eq(2)
    converter.__test_raw_flag_condition_state("compare_versions(\"1.0.0\", \"2.0.0\") > 0").should eq(1)
    converter.__test_raw_flag_condition_state("compare_versions(\"1.0.0\", \"2.0.0\") ~= 0").should eq(0)
  end

  it "evaluates nested grouped short-circuit expressions" do
    converter = raw_flag_converter(Set{"enabled"})

    converter.__test_raw_flag_condition_state(
      "(flag?(:enabled) || (unresolved_condition && flag?(:disabled))) && flag?(:enabled)",
    ).should eq(2)
    converter.__test_raw_flag_condition_state(
      "(flag?(:disabled) && (unresolved_condition || flag?(:enabled))) || flag?(:enabled)",
    ).should eq(2)
  end
end
