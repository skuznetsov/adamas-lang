require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_method_name_contract(name : String)
    cached = parse_method_name(name)
    uncached = parse_method_name_uncached(name)
    compact = parse_method_name_compact(name)
    {
      cached:          {cached.owner, cached.method, cached.suffix, cached.separator, cached.base},
      uncached:        {uncached.owner, uncached.method, uncached.suffix, uncached.separator, uncached.base},
      compact:         {compact.owner, compact.method, compact.separator, compact.base},
      owner_from_name: method_owner_from_name(name),
      short_name:      method_short_from_name(name),
      suffix:          method_suffix(name),
      stripped:        strip_type_suffix(name),
      is_class:        class_method?(name),
      is_instance:     instance_method?(name),
      has_separator:   has_method_separator?(name),
    }
  end

  def __test_parse_method_name_compact(name : String)
    parts = parse_method_name_compact(name)
    {parts.owner, parts.method, parts.separator, parts.base}
  end
end

describe "compact method-name parsing" do
  it "preserves owner, method, separator, and unspecialized base" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_parse_method_name_compact("Outer::Owner#call$Int32").should eq(
      {"Outer::Owner", "call", '#', "Outer::Owner#call"}
    )
    converter.__test_parse_method_name_compact("Owner.build$String").should eq(
      {"Owner", "build", '.', "Owner.build"}
    )
    converter.__test_parse_method_name_compact("Outer.Inner#call$Int32").should eq(
      {"Outer.Inner", "call", '#', "Outer.Inner#call"}
    )
    converter.__test_parse_method_name_compact("Outer#Inner#call").should eq(
      {"Outer#Inner", "call", '#', "Outer#Inner#call"}
    )
    converter.__test_parse_method_name_compact("Owner#method.other$T").should eq(
      {"Owner", "method.other", '#', "Owner#method.other"}
    )
    converter.__test_parse_method_name_compact("Owner.one.two$T").should eq(
      {"Owner", "one.two", '.', "Owner.one.two"}
    )
    converter.__test_parse_method_name_compact("Owner$T#method").should eq(
      {"Owner$T#method", nil, nil, "Owner"}
    )
    converter.__test_parse_method_name_compact("call$Int32").should eq(
      {"call$Int32", nil, nil, "call"}
    )
    converter.__test_parse_method_name_compact("call").should eq(
      {"call", nil, nil, "call"}
    )
  end

  it "keeps nested type-literal dots inside generic owners and specialization suffixes" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    owner = "Box(Proc(Int32.class, Int32))"
    suffix = "Tuple(Proc(Int32.class, Int32), String.class)"
    instance_name = "#{owner}#foo$#{suffix}"
    instance_base = "#{owner}#foo"

    instance = converter.__test_method_name_contract(instance_name)
    instance[:cached].should eq({owner, "foo", suffix, '#', instance_base})
    instance[:uncached].should eq({owner, "foo", suffix, '#', instance_base})
    instance[:compact].should eq({owner, "foo", '#', instance_base})
    instance[:owner_from_name].should eq(owner)
    instance[:short_name].should eq("foo")
    instance[:suffix].should eq(suffix)
    instance[:stripped].should eq(instance_base)
    instance[:is_class].should be_false
    instance[:is_instance].should be_true
    instance[:has_separator].should be_true

    class_name = "#{owner}.foo$#{suffix}"
    class_base = "#{owner}.foo"
    class_method = converter.__test_method_name_contract(class_name)
    class_method[:cached].should eq({owner, "foo", suffix, '.', class_base})
    class_method[:uncached].should eq({owner, "foo", suffix, '.', class_base})
    class_method[:compact].should eq({owner, "foo", '.', class_base})
    class_method[:owner_from_name].should eq(owner)
    class_method[:short_name].should eq("foo")
    class_method[:suffix].should eq(suffix)
    class_method[:stripped].should eq(class_base)
    class_method[:is_class].should be_true
    class_method[:is_instance].should be_false
    class_method[:has_separator].should be_true
  end

  it "keeps free names, operator names, and top-level separator precedence stable" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    nested_type = "Proc(Int32.class, Tuple(String.class, Int32))"
    free = converter.__test_method_name_contract(nested_type)
    free[:cached].should eq({nested_type, nil, nil, nil, nested_type})
    free[:uncached].should eq({nested_type, nil, nil, nil, nested_type})
    free[:compact].should eq({nested_type, nil, nil, nested_type})
    free[:owner_from_name].should eq(nested_type)
    free[:short_name].should be_nil
    free[:suffix].should be_nil
    free[:is_class].should be_false
    free[:is_instance].should be_false
    free[:has_separator].should be_false

    operator = converter.__test_method_name_contract("Owner#[]=$Tuple(Int32.class, String)")
    operator[:cached].should eq({"Owner", "[]=", "Tuple(Int32.class, String)", '#', "Owner#[]="})
    operator[:short_name].should eq("[]=")
    operator[:is_instance].should be_true
    operator[:is_class].should be_false

    class_operator = converter.__test_method_name_contract("Owner.+$Tuple(Int32.class, String)")
    class_operator[:cached].should eq({"Owner", "+", "Tuple(Int32.class, String)", '.', "Owner.+"})
    class_operator[:short_name].should eq("+")
    class_operator[:is_class].should be_true
    class_operator[:is_instance].should be_false

    dot_then_hash = converter.__test_method_name_contract("Outer.Inner#call$Int32")
    dot_then_hash[:cached].should eq({"Outer.Inner", "call", "Int32", '#', "Outer.Inner#call"})
    dot_then_hash[:is_instance].should be_true
    dot_then_hash[:is_class].should be_false

    dotted_method = converter.__test_method_name_contract("Owner#method.other$T")
    dotted_method[:cached].should eq({"Owner", "method.other", "T", '#', "Owner#method.other"})
    dotted_method[:short_name].should eq("method.other")
    dotted_method[:is_instance].should be_true
    dotted_method[:is_class].should be_false

    pre_separator_suffix = converter.__test_method_name_contract("Owner$T#method")
    pre_separator_suffix[:cached].should eq({"Owner", nil, "T#method", nil, "Owner"})
    pre_separator_suffix[:compact].should eq({"Owner$T#method", nil, nil, "Owner"})
    pre_separator_suffix[:is_instance].should be_false
    pre_separator_suffix[:is_class].should be_false
  end
end
