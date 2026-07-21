require "../spec_helper"
require "../../src/compiler/hir/hir"
require "../../src/compiler/hir/lower_missing_ledger"

describe Adamas::HIR::LowerMissingDemandLedger do
  it "streams typed rows with a strict cap and overflow summary" do
    output = IO::Memory.new
    ledger = Adamas::HIR::LowerMissingDemandLedger.new(1, output)

    ledger.queued(
      3,
      Adamas::HIR::LowerMissingDemandContext::Initial,
      Adamas::HIR::LowerMissingDemandReason::CallTarget,
      "Array(Int32)#push$Int32",
      10,
      2,
    )
    ledger.outcome(
      "Array(Int32)#push$Int32",
      Adamas::HIR::LowerMissingDemandOutcome::Materialized,
      11,
      0,
    )
    ledger.queued(
      4,
      Adamas::HIR::LowerMissingDemandContext::Initial,
      Adamas::HIR::LowerMissingDemandReason::CallTarget,
      "Array(String)#push$String",
      11,
      1,
    )
    ledger.outcome(
      "Array(String)#push$String",
      Adamas::HIR::LowerMissingDemandOutcome::Materialized,
      12,
      0,
    )
    ledger.summary(4, Adamas::HIR::LowerMissingDemandContext::Initial)

    text = output.to_s
    text.should contain("schema=lower_missing_demand_v1")
    text.should contain("event=demand")
    text.lines.count { |line| line.includes?("event=demand") }.should eq(1)
    text.should contain("context=initial")
    text.should contain("reason=call_target")
    text.should contain("owner_kind=instance")
    text.should contain("requested_id=0x")
    text.should_not contain("materialized_id=0x0")
    text.should contain("handoff=0")
    text.should contain("event=summary")
    text.should contain("emitted=1")
    text.should contain("overflow=1")
    text.should contain("outcome=materialized")
    text.should contain("function_count_before=10")
    text.should contain("function_count_after=11")
  end

  it "reports multiple observed HIR shapes under one rendered request" do
    output = IO::Memory.new
    ledger = Adamas::HIR::LowerMissingDemandLedger.new(4, output, 20, 0)
    name = "Box#push$Value"

    ledger.checkpoint(0, Adamas::HIR::LowerMissingDemandContext::Initial, false)
    ledger.observe(name, nil, [Adamas::HIR::TypeRef::INT32], false)
    ledger.observe(name, nil, [Adamas::HIR::TypeRef::STRING], false)
    ledger.queued(
      0,
      Adamas::HIR::LowerMissingDemandContext::Initial,
      Adamas::HIR::LowerMissingDemandReason::CallTarget,
      name,
      20,
      1,
    )
    ledger.outcome(name, Adamas::HIR::LowerMissingDemandOutcome::Deferred, 20, 1)
    ledger.summary(1, Adamas::HIR::LowerMissingDemandContext::Initial, 20, 1)

    text = output.to_s
    text.should contain("event=checkpoint")
    text.should contain("shape_mismatch_count=1")
    text.should contain("shape_ambiguous=1")
    text.should contain("outcome=deferred")
    text.should contain("function_count_start=20")
    text.should contain("function_count_end=20")
  end
end
