require "../spec_helper"
require "../../src/compiler/hir/hir"

describe "missing-call revision ledger" do
  it "tracks function identity replacement without resetting revisions" do
    hir_module = Adamas::HIR::Module.new("revision_probe")

    initial_revision = hir_module.function_set_revision
    original = hir_module.create_function(
      "Owner#target",
      Adamas::HIR::TypeRef::VOID,
    )
    created_revision = hir_module.function_set_revision
    created_revision.should be > initial_revision

    hir_module.create_function(
      "Owner#target",
      Adamas::HIR::TypeRef::VOID,
    ).same?(original).should be_true
    hir_module.function_set_revision.should eq(created_revision)

    hir_module.remove_function("Owner#target").should be_true
    removed_revision = hir_module.function_set_revision
    removed_revision.should be > created_revision

    replacement = hir_module.create_function(
      "Owner#target",
      Adamas::HIR::TypeRef::VOID,
    )
    replacement.id.should_not eq(original.id)
    hir_module.function_set_revision.should be > removed_revision

    before_reset = hir_module.function_set_revision
    hir_module.bootstrap_reinitialize_runtime_state
    hir_module.function_set_revision.should be > before_reset
  end

  it "separates body mutations from call-demand mutations" do
    hir_module = Adamas::HIR::Module.new("revision_probe")
    function = hir_module.create_function(
      "Owner#caller",
      Adamas::HIR::TypeRef::VOID,
    )
    block = function.get_block(function.entry_block)

    initial_body_revision = function.body_revision
    initial_demand_revision = function.demand_revision
    initial_module_body_revision = hir_module.hir_body_revision

    block.add(
      Adamas::HIR::Literal.new(
        function.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        1_i64,
      )
    )
    function.body_revision.should be > initial_body_revision
    function.demand_revision.should eq(initial_demand_revision)
    hir_module.hir_body_revision.should be > initial_module_body_revision

    call = Adamas::HIR::Call.new(
      function.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      "Owner#first",
    )
    block.add(call)
    demand_after_add = function.demand_revision
    demand_after_add.should be > initial_demand_revision

    function.rewrite_call_method_name(call, "Owner#second").should be_true
    function.demand_revision.should be > demand_after_add
    demand_after_rewrite = function.demand_revision

    function.rewrite_call_method_name(call, "Owner#second").should be_false
    function.demand_revision.should eq(demand_after_rewrite)

    function.append_call_arg(call, function.next_value_id)
    function.body_revision.should be > initial_body_revision
    function.demand_revision.should be > demand_after_rewrite
  end

  it "tracks scan-side instruction insertion and terminator replacement" do
    hir_module = Adamas::HIR::Module.new("revision_probe")
    function = hir_module.create_function(
      "Owner#caller",
      Adamas::HIR::TypeRef::VOID,
    )
    block = function.get_block(function.entry_block)

    before_insert = function.body_revision
    block.insert(
      0,
      Adamas::HIR::Literal.new(
        function.next_value_id,
        Adamas::HIR::TypeRef::BOOL,
        false,
      )
    )
    function.body_revision.should be > before_insert

    before_terminator = function.body_revision
    block.terminator = Adamas::HIR::Return.new
    function.body_revision.should be > before_terminator
  end
end
