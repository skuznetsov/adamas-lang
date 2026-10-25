require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/ast_to_hir"

private alias ModuleDefList = Array({Adamas::Compiler::Frontend::ModuleNode, Adamas::Compiler::Frontend::ArenaLike})

private def build_hierarchy(classes : Array(String), modules : Array(String)) : Adamas::HIR::TypeHierarchy
  class_info = {} of String => Adamas::HIR::ClassInfo
  classes.each do |name|
    class_info[name] = Adamas::HIR::ClassInfo.new(
      name, Adamas::HIR::TypeRef::VOID, [] of Adamas::HIR::IVarInfo, [] of Adamas::HIR::ClassVarInfo, 0)
  end
  module_defs = {} of String => ModuleDefList
  modules.each { |name| module_defs[name] = ModuleDefList.new }
  Adamas::HIR::TypeHierarchy.new(class_info, module_defs)
end

private def transitive_includers(hierarchy, owner) : Array({String, Bool})
  result = [] of {String, Bool}
  hierarchy.each_transitive_includer(owner) { |name, is_module| result << {name, is_module} }
  result
end

describe Adamas::HIR::TypeHierarchy do
  it "reaches classes through modules that include modules" do
    h = build_hierarchy(%w(C D), %w(M1 M2))
    h.add_inclusion("M1", "M2")
    h.add_inclusion("M2", "C")
    h.add_parent_edge("D", "C")

    transitive_includers(h, "M1").should eq([{"M2", true}, {"C", false}])
    h.dispatch_targets("M1").should eq(%w(C D))
  end

  it "reports class-only includers through included modules" do
    h = build_hierarchy(%w(C), %w(M1 M2 M3))
    h.add_inclusion("M1", "M2")
    h.class_only_includers?("M1").should be_false
    h.class_only_includers?("M3").should be_false

    h.add_inclusion("M2", "C")
    h.class_only_includers?("M1").should be_true
    h.class_only_includers?("M1(Int32)").should be_true
  end

  it "rejects a module with a struct or unknown includer" do
    class_info = {} of String => Adamas::HIR::ClassInfo
    {"C" => false, "S" => true}.each do |name, is_struct|
      class_info[name] = Adamas::HIR::ClassInfo.new(
        name, Adamas::HIR::TypeRef::VOID, [] of Adamas::HIR::IVarInfo, [] of Adamas::HIR::ClassVarInfo, 0, is_struct)
    end
    module_defs = {} of String => ModuleDefList
    module_defs["M"] = ModuleDefList.new
    h = Adamas::HIR::TypeHierarchy.new(class_info, module_defs)
    h.add_inclusion("M", "C")
    h.class_only_includers?("M").should be_true

    h.add_inclusion("M", "S")
    h.class_only_includers?("M").should be_false

    h2 = build_hierarchy(%w(C), %w(N))
    h2.add_inclusion("N", "C")
    h2.add_inclusion("N", "Unknown")
    h2.class_only_includers?("N").should be_false
  end

  it "yields a diamond includer once" do
    h = build_hierarchy(%w(C), %w(M1 M2 M3))
    h.add_inclusion("M1", "M2")
    h.add_inclusion("M1", "M3")
    h.add_inclusion("M2", "C")
    h.add_inclusion("M3", "C")
    # Classes are also recorded under every transitively included module.
    h.add_inclusion("M1", "C")

    transitive_includers(h, "M1").map(&.[0]).should eq(%w(M2 M3 C))
    h.dispatch_targets("M1").should eq(%w(C))
  end

  it "looks up a generic module owner by its base name" do
    h = build_hierarchy(%w(Box(Int32)), %w(En))
    h.add_inclusion("En", "Box(Int32)")

    h.dispatch_targets("En(Int32)").should eq(%w(Box(Int32)))
  end

  it "lists subclasses of a class owner without includers" do
    h = build_hierarchy(%w(A B C), [] of String)
    h.add_parent_edge("B", "A")
    h.add_parent_edge("C", "B")

    h.dispatch_targets("A").should eq(%w(B C))
    h.dispatch_targets("C").should be_empty
  end

  it "invalidates cached subclasses when a descendant edge is added" do
    h = build_hierarchy(%w(A B C), [] of String)
    h.add_parent_edge("B", "A").should_not be_nil
    h.subclasses("A").should eq(%w(B))

    h.add_parent_edge("C", "B")
    h.subclasses("A").should eq(%w(B C))
    h.add_parent_edge("C", "B").should be_nil
  end

  it "registers children under every parent spelling" do
    h = build_hierarchy(%w(Kid), [] of String)
    h.add_parent_edge("Kid", "Ns::Base(T)")

    {"Ns::Base(T)", "Ns::Base", "Base(T)", "Base"}.each do |key|
      h.direct_children(key).try(&.to_a).should eq(%w(Kid))
    end
  end

  it "resolves includer keys by exact name, unique suffix and short name" do
    h = build_hierarchy(%w(C D E), %w(A::B::M X::N Y::N M2))
    h.add_inclusion("A::B::M", "C")
    h.add_inclusion("X::N", "D")
    h.add_inclusion("Y::N", "E")
    h.add_inclusion("M2", "C")

    exact = h.includer_lookup("A::B::M")
    exact.module_base.should eq("A::B::M")
    exact.includers.try(&.to_a).should eq(%w(C))

    suffix = h.includer_lookup("B::M")
    suffix.module_base.should eq("A::B::M")
    suffix.includers.try(&.to_a).should eq(%w(C))

    # A short-name hit keeps the spelling that was asked for.
    short = h.includer_lookup("Q::M2")
    short.module_base.should eq("Q::M2")
    short.includers.try(&.to_a).should eq(%w(C))

    # `N` is a suffix of two keys: ambiguous, no includers.
    ambiguous = h.includer_lookup("N")
    ambiguous.module_base.should eq("N")
    ambiguous.includers.should be_nil
  end

  it "indexes suffixes of the generic module base" do
    h = build_hierarchy(%w(C), %w(Ns::G))
    h.add_inclusion("Ns::G(T)", "C").should be_true
    h.add_inclusion("Ns::G(T)", "C").should be_false

    h.includer_key?("G").should be_true
    h.includer_key?("Ns::G").should be_true
    h.includer_key?("H").should be_false
    h.includer_lookup("G").module_base.should eq("Ns::G(T)")
  end
end
