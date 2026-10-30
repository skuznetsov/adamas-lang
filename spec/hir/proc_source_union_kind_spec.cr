require "../spec_helper"
require "../../src/compiler/hir/hir"

describe "HIR Proc source type facts" do
  it "keeps mixed-kind Proc metadata distinct from the same pure carrier" do
    mod = Adamas::HIR::Module.new("proc_source_union_kind")
    params = [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32]
    mixed_facts = [
      [{Adamas::HIR::TypeRef::INT32, false}, {Adamas::HIR::TypeRef::INT32, true}],
      [] of {Adamas::HIR::TypeRef, Bool},
    ]
    mixed = Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32, Int32)",
      params,
      [false, false],
      mixed_facts,
    )
    pure = Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32, Int32)",
      params,
      [false, false],
    )

    mixed.should_not eq(pure)
    mixed_ref = mod.intern_type(mixed)
    pure_ref = mod.intern_type(pure)
    mixed_ref.should_not eq(pure_ref)
    mixed.proc_source_type_facts_at(0).should eq([
      {Adamas::HIR::TypeRef::INT32, false},
      {Adamas::HIR::TypeRef::INT32, true},
    ])
    mixed.proc_source_type_facts_at(1).should be_nil
  end

  it "canonicalizes fact order and duplicates before interning" do
    mod = Adamas::HIR::Module.new("proc_source_union_kind_canonical")
    params = [Adamas::HIR::TypeRef::INT32]
    ordered = Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32)",
      params,
      proc_source_type_facts: [[
        {Adamas::HIR::TypeRef::INT32, false},
        {Adamas::HIR::TypeRef::INT32, true},
      ]],
    )
    reordered = Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32)",
      params,
      proc_source_type_facts: [[
        {Adamas::HIR::TypeRef::INT32, true},
        {Adamas::HIR::TypeRef::INT32, false},
        {Adamas::HIR::TypeRef::INT32, true},
      ]],
    )

    ordered.proc_source_type_facts.should eq(reordered.proc_source_type_facts)
    mod.intern_type(ordered).should eq(mod.intern_type(reordered))
  end

  it "owns the supplied fact arrays and drops slots without both kinds" do
    facts = Array(Array({Adamas::HIR::TypeRef, Bool})).new
    facts << [
      {Adamas::HIR::TypeRef::INT32, false},
      {Adamas::HIR::TypeRef::INT32, true},
    ]
    facts << [{Adamas::HIR::TypeRef::INT64, true}]
    descriptor = Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32, Int64)",
      [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT64],
      proc_source_type_facts: facts,
    )

    facts[0] << {Adamas::HIR::TypeRef::INT64, false}
    facts[1] << {Adamas::HIR::TypeRef::INT64, false}
    facts[1].clear

    descriptor.proc_source_type_facts_at(0).should eq([
      {Adamas::HIR::TypeRef::INT32, false},
      {Adamas::HIR::TypeRef::INT32, true},
    ])
    descriptor.proc_source_type_facts_at(1).should be_nil
    descriptor.proc_source_type_facts_at(2).should be_nil
  end

  it "validates Proc fact metadata arity and preserves the old defaults" do
    expect_raises(ArgumentError) do
      Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Proc,
        "Proc(Int32, Int32)",
        [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32],
        proc_source_type_facts: [[
          {Adamas::HIR::TypeRef::INT32, false},
          {Adamas::HIR::TypeRef::INT32, true},
        ]],
      )
    end
    expect_raises(ArgumentError) do
      Adamas::HIR::TypeDescriptor.new(
        Adamas::HIR::TypeKind::Class,
        "NotProc",
        proc_source_type_facts: [[{Adamas::HIR::TypeRef::INT32, false}]],
      )
    end

    default = Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32, Int32)",
      [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32],
    )
    default.proc_type_literal_slots.should be_nil
    default.proc_type_literal_slot?(0).should be_false
    default.proc_source_type_facts.should be_nil
    default.proc_source_type_facts_at(0).should be_nil

    empty_facts = Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32, Int32)",
      [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32],
      proc_source_type_facts: [
        [] of {Adamas::HIR::TypeRef, Bool},
        [] of {Adamas::HIR::TypeRef, Bool},
      ],
    )
    empty_facts.proc_source_type_facts.should be_nil

    explicit_literals = Adamas::HIR::TypeDescriptor.new(
      Adamas::HIR::TypeKind::Proc,
      "Proc(Int32, Int32)",
      [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::INT32],
      [true, false],
    )
    explicit_literals.proc_type_literal_slot?(0).should be_true
    explicit_literals.proc_type_literal_slot?(1).should be_false
    explicit_literals.proc_source_type_facts.should be_nil
  end
end
