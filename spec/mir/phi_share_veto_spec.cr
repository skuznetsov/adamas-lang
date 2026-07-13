require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

private def with_phi_share_mode(veto : Bool, function_name : String, & : -> String) : String
  previous_veto = ENV["ADAMAS_PHI_SHARE_VETO"]?
  previous_filter = ENV["ADAMAS_PHI_SHARE_VETO_FILTER"]?
  previous_legacy = ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"]?
  if veto
    ENV["ADAMAS_PHI_SHARE_VETO"] = "1"
    ENV.delete("ADAMAS_PHI_SHARE_VETO_FILTER")
    ENV.delete("ADAMAS_PHI_SHARE_LEGACY_FILTER")
  else
    ENV.delete("ADAMAS_PHI_SHARE_VETO")
    ENV.delete("ADAMAS_PHI_SHARE_VETO_FILTER")
    ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"] = function_name
  end
  yield
ensure
  if previous_veto
    ENV["ADAMAS_PHI_SHARE_VETO"] = previous_veto
  else
    ENV.delete("ADAMAS_PHI_SHARE_VETO")
  end
  if previous_filter
    ENV["ADAMAS_PHI_SHARE_VETO_FILTER"] = previous_filter
  else
    ENV.delete("ADAMAS_PHI_SHARE_VETO_FILTER")
  end
  if previous_legacy
    ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"] = previous_legacy
  else
    ENV.delete("ADAMAS_PHI_SHARE_LEGACY_FILTER")
  end
end

private def phi_share_body(mod : Adamas::MIR::Module, function_name : String, veto : Bool) : String
  with_phi_share_mode(veto, function_name) do
    generator = Adamas::MIR::LLVMIRGenerator.new(mod)
    generator.emit_type_metadata = false
    output = generator.generate
    output[/define i32 @#{Regex.escape(function_name)}\(\) \{.*?\n\}/m].not_nil!
  end
end

private def phi_share_default_body(mod : Adamas::MIR::Module, function_name : String) : String
  previous_veto = ENV["ADAMAS_PHI_SHARE_VETO"]?
  previous_filter = ENV["ADAMAS_PHI_SHARE_VETO_FILTER"]?
  previous_legacy = ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"]?
  ENV.delete("ADAMAS_PHI_SHARE_VETO")
  ENV.delete("ADAMAS_PHI_SHARE_VETO_FILTER")
  ENV.delete("ADAMAS_PHI_SHARE_LEGACY_FILTER")
  generator = Adamas::MIR::LLVMIRGenerator.new(mod)
  generator.emit_type_metadata = false
  output = generator.generate
  output[/define i32 @#{Regex.escape(function_name)}\(\) \{.*?\n\}/m].not_nil!
ensure
  if previous_veto
    ENV["ADAMAS_PHI_SHARE_VETO"] = previous_veto
  else
    ENV.delete("ADAMAS_PHI_SHARE_VETO")
  end
  if previous_filter
    ENV["ADAMAS_PHI_SHARE_VETO_FILTER"] = previous_filter
  else
    ENV.delete("ADAMAS_PHI_SHARE_VETO_FILTER")
  end
  if previous_legacy
    ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"] = previous_legacy
  else
    ENV.delete("ADAMAS_PHI_SHARE_LEGACY_FILTER")
  end
end

private def phi_share_configured_body(
  mod : Adamas::MIR::Module,
  function_name : String,
  veto : String? = nil,
  filter : String? = nil,
  legacy_filter : String? = nil,
) : String
  previous_veto = ENV["ADAMAS_PHI_SHARE_VETO"]?
  previous_filter = ENV["ADAMAS_PHI_SHARE_VETO_FILTER"]?
  previous_legacy = ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"]?
  if veto
    ENV["ADAMAS_PHI_SHARE_VETO"] = veto
  else
    ENV.delete("ADAMAS_PHI_SHARE_VETO")
  end
  if filter
    ENV["ADAMAS_PHI_SHARE_VETO_FILTER"] = filter
  else
    ENV.delete("ADAMAS_PHI_SHARE_VETO_FILTER")
  end
  if legacy_filter
    ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"] = legacy_filter
  else
    ENV.delete("ADAMAS_PHI_SHARE_LEGACY_FILTER")
  end
  generator = Adamas::MIR::LLVMIRGenerator.new(mod)
  generator.emit_type_metadata = false
  output = generator.generate
  output[/define i32 @#{Regex.escape(function_name)}\(\) \{.*?\n\}/m].not_nil!
ensure
  if previous_veto
    ENV["ADAMAS_PHI_SHARE_VETO"] = previous_veto
  else
    ENV.delete("ADAMAS_PHI_SHARE_VETO")
  end
  if previous_filter
    ENV["ADAMAS_PHI_SHARE_VETO_FILTER"] = previous_filter
  else
    ENV.delete("ADAMAS_PHI_SHARE_VETO_FILTER")
  end
  if previous_legacy
    ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"] = previous_legacy
  else
    ENV.delete("ADAMAS_PHI_SHARE_LEGACY_FILTER")
  end
end

private def extern_value(builder : Adamas::MIR::Builder, name : String) : Adamas::MIR::ValueId
  builder.extern_call(name, Array(Adamas::MIR::ValueId).new, Adamas::MIR::TypeRef::INT32)
end

private def four_arm_entry(
  builder : Adamas::MIR::Builder,
  entry : Adamas::MIR::BlockId,
  arm0 : Adamas::MIR::BlockId,
  arm2 : Adamas::MIR::BlockId,
  arm3 : Adamas::MIR::BlockId,
) : Nil
  switch_value = builder.const_int(0_i64, Adamas::MIR::TypeRef::INT32)
  builder.switch(switch_value, [{0_i64, arm0}, {1_i64, arm2}], arm3)
end

private def build_tuple_store_module : Adamas::MIR::Module
  module_ = Adamas::MIR::Module.new("phi_tuple_store")
  function_name = "phi_tuple_store"
  function = module_.create_function(function_name, Adamas::MIR::TypeRef::INT32)
  builder = Adamas::MIR::Builder.new(function)
  entry = function.entry_block
  arm0 = function.create_block
  arm1 = function.create_block
  arm2 = function.create_block
  arm3 = function.create_block
  merge = function.create_block
  four_arm_entry(builder, entry, arm0, arm2, arm3)

  builder.current_block = arm0
  parent = extern_value(builder, "phi_parent")
  split = builder.extern_call("phi_split", Array(Adamas::MIR::ValueId).new, Adamas::MIR::TypeRef::BOOL)
  builder.branch(split, arm1, merge)

  builder.current_block = arm1
  branch_value = extern_value(builder, "phi_branch")
  payload = builder.alloc(Adamas::MIR::MemoryStrategy::Stack, Adamas::MIR::TypeRef::INT32, 8_u64, 4_u32)
  first = builder.gep(payload, [0_u32], Adamas::MIR::TypeRef::POINTER)
  builder.store(first, parent)
  second = builder.gep(payload, [4_u32], Adamas::MIR::TypeRef::POINTER)
  builder.store(second, branch_value)
  builder.jump(merge)

  builder.current_block = arm2
  arm2_value = extern_value(builder, "phi_arm2")
  builder.jump(merge)

  builder.current_block = arm3
  arm3_value = extern_value(builder, "phi_arm3")
  builder.jump(merge)

  builder.current_block = merge
  state = builder.phi(Adamas::MIR::TypeRef::INT32)
  state.add_incoming(from: arm0, value: parent)
  state.add_incoming(from: arm1, value: branch_value)
  state.add_incoming(from: arm2, value: arm2_value)
  state.add_incoming(from: arm3, value: arm3_value)
  builder.ret(state.id)
  function.compute_predecessors
  module_
end

private def build_safe_share_module : Adamas::MIR::Module
  module_ = Adamas::MIR::Module.new("phi_safe_share")
  function_name = "phi_safe_share"
  function = module_.create_function(function_name, Adamas::MIR::TypeRef::INT32)
  builder = Adamas::MIR::Builder.new(function)
  entry = function.entry_block
  arm0 = function.create_block
  arm1 = function.create_block
  arm2 = function.create_block
  arm3 = function.create_block
  merge = function.create_block
  four_arm_entry(builder, entry, arm0, arm2, arm3)

  builder.current_block = arm0
  arm0_value = extern_value(builder, "phi_safe0")
  split = builder.extern_call("phi_safe_split", Array(Adamas::MIR::ValueId).new, Adamas::MIR::TypeRef::BOOL)
  builder.branch(split, arm1, merge)

  builder.current_block = arm1
  arm1_value = extern_value(builder, "phi_safe1")
  builder.jump(merge)

  builder.current_block = arm2
  arm2_value = extern_value(builder, "phi_safe2")
  builder.jump(merge)

  builder.current_block = arm3
  arm3_value = extern_value(builder, "phi_safe3")
  builder.jump(merge)

  builder.current_block = merge
  state = builder.phi(Adamas::MIR::TypeRef::INT32)
  state.add_incoming(from: arm0, value: arm0_value)
  state.add_incoming(from: arm1, value: arm1_value)
  state.add_incoming(from: arm2, value: arm2_value)
  state.add_incoming(from: arm3, value: arm3_value)
  builder.ret(state.id)
  function.compute_predecessors
  module_
end

private def build_call_co_use_module : Adamas::MIR::Module
  module_ = Adamas::MIR::Module.new("phi_call_co_use")
  function_name = "phi_call_co_use"
  function = module_.create_function(function_name, Adamas::MIR::TypeRef::INT32)
  builder = Adamas::MIR::Builder.new(function)
  entry = function.entry_block
  arm0 = function.create_block
  arm1 = function.create_block
  arm2 = function.create_block
  arm3 = function.create_block
  merge = function.create_block
  four_arm_entry(builder, entry, arm0, arm2, arm3)

  builder.current_block = arm0
  parent = extern_value(builder, "phi_parent_call")
  split = builder.extern_call("phi_split_call", Array(Adamas::MIR::ValueId).new, Adamas::MIR::TypeRef::BOOL)
  builder.branch(split, arm1, merge)

  builder.current_block = arm1
  branch_value = extern_value(builder, "phi_branch_call")
  builder.extern_call("phi_consume", [parent, branch_value], Adamas::MIR::TypeRef::INT32)
  builder.jump(merge)

  builder.current_block = arm2
  arm2_value = extern_value(builder, "phi_arm2_call")
  builder.jump(merge)

  builder.current_block = arm3
  arm3_value = extern_value(builder, "phi_arm3_call")
  builder.jump(merge)

  builder.current_block = merge
  state = builder.phi(Adamas::MIR::TypeRef::INT32)
  state.add_incoming(from: arm0, value: parent)
  state.add_incoming(from: arm1, value: branch_value)
  state.add_incoming(from: arm2, value: arm2_value)
  state.add_incoming(from: arm3, value: arm3_value)
  builder.ret(state.id)
  function.compute_predecessors
  module_
end

private def build_one_live_module : Adamas::MIR::Module
  module_ = Adamas::MIR::Module.new("phi_one_live")
  function_name = "phi_one_live"
  function = module_.create_function(function_name, Adamas::MIR::TypeRef::INT32)
  builder = Adamas::MIR::Builder.new(function)
  entry = function.entry_block
  arm0 = function.create_block
  arm1 = function.create_block
  arm2 = function.create_block
  arm3 = function.create_block
  merge = function.create_block
  four_arm_entry(builder, entry, arm0, arm2, arm3)

  builder.current_block = arm0
  live_value = extern_value(builder, "phi_live")
  builder.extern_call("phi_consume_one", [live_value], Adamas::MIR::TypeRef::INT32)
  builder.jump(merge)

  builder.current_block = arm1
  dead_value = extern_value(builder, "phi_dead1")
  builder.jump(merge)

  builder.current_block = arm2
  dead_value2 = extern_value(builder, "phi_dead2")
  builder.jump(merge)

  builder.current_block = arm3
  dead_value3 = extern_value(builder, "phi_dead3")
  builder.jump(merge)

  builder.current_block = merge
  state = builder.phi(Adamas::MIR::TypeRef::INT32)
  state.add_incoming(from: arm0, value: live_value)
  state.add_incoming(from: arm1, value: dead_value)
  state.add_incoming(from: arm2, value: dead_value2)
  state.add_incoming(from: arm3, value: dead_value3)
  builder.ret(state.id)
  function.compute_predecessors
  module_
end

describe "phi shared-slot veto" do
  it "fixes tuple-field carrier aliasing under the explicit veto" do
    module_ = build_tuple_store_module
    legacy = phi_share_body(module_, "phi_tuple_store", veto: false)
    vetoed = phi_share_body(module_, "phi_tuple_store", veto: true)

    legacy.should contain("phi_slot")
    vetoed.should_not contain("phi_slot")
  end

  it "fixes valid non-Phi call co-use under the explicit veto" do
    module_ = build_call_co_use_module
    legacy = phi_share_body(module_, "phi_call_co_use", veto: false)
    vetoed = phi_share_body(module_, "phi_call_co_use", veto: true)

    legacy.should contain("phi_slot")
    vetoed.should_not contain("phi_slot")
  end

  it "drops one-live/three-dead sharing under the explicit veto" do
    module_ = build_one_live_module
    legacy = phi_share_body(module_, "phi_one_live", veto: false)
    vetoed = phi_share_body(module_, "phi_one_live", veto: true)

    legacy.should contain("phi_slot")
    vetoed.should_not contain("phi_slot")
  end

  it "keeps the liveness veto enabled by default" do
    phi_share_default_body(build_tuple_store_module, "phi_tuple_store").should_not contain("phi_slot")
    phi_share_default_body(build_call_co_use_module, "phi_call_co_use").should_not contain("phi_slot")
    phi_share_default_body(build_one_live_module, "phi_one_live").should_not contain("phi_slot")
  end

  it "keeps safe four-way phi sharing when every incoming dies at the phi" do
    phi_share_default_body(build_safe_share_module, "phi_safe_share").should contain("phi_slot")
  end

  it "honors filter gates and explicit-veto precedence" do
    matching_veto = phi_share_configured_body(
      build_tuple_store_module,
      "phi_tuple_store",
      filter: "phi_tuple_store"
    )
    matching_veto.should_not contain("phi_slot")

    nonmatching_veto = phi_share_configured_body(
      build_tuple_store_module,
      "phi_tuple_store",
      filter: "some_other_function"
    )
    nonmatching_veto.should contain("phi_slot")

    matching_legacy = phi_share_configured_body(
      build_tuple_store_module,
      "phi_tuple_store",
      legacy_filter: "phi_tuple_store"
    )
    matching_legacy.should contain("phi_slot")

    nonmatching_legacy = phi_share_configured_body(
      build_tuple_store_module,
      "phi_tuple_store",
      legacy_filter: "some_other_function"
    )
    nonmatching_legacy.should_not contain("phi_slot")

    explicit_veto = phi_share_configured_body(
      build_tuple_store_module,
      "phi_tuple_store",
      veto: "1",
      filter: "some_other_function",
      legacy_filter: "phi_tuple_store"
    )
    explicit_veto.should_not contain("phi_slot")
  end

  it "isolates explicit modes from ambient filters and restores empty values" do
    previous_veto = ENV["ADAMAS_PHI_SHARE_VETO"]?
    previous_filter = ENV["ADAMAS_PHI_SHARE_VETO_FILTER"]?
    previous_legacy = ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"]?
    begin
      # An ambient matching VETO_FILTER must not override the helper's legacy
      # mode; the helper clears both filters before generating the body.
      ENV["ADAMAS_PHI_SHARE_VETO"] = ""
      ENV["ADAMAS_PHI_SHARE_VETO_FILTER"] = "phi_tuple_store"
      ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"] = "some_other_function"
      legacy = phi_share_body(build_tuple_store_module, "phi_tuple_store", veto: false)
      legacy.should contain("phi_slot")
      ENV["ADAMAS_PHI_SHARE_VETO"]?.should eq("")
      ENV["ADAMAS_PHI_SHARE_VETO_FILTER"]?.should eq("phi_tuple_store")
      ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"]?.should eq("some_other_function")

      # Conversely, an ambient legacy match must not override explicit veto.
      ENV["ADAMAS_PHI_SHARE_VETO_FILTER"] = "some_other_function"
      ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"] = "phi_tuple_store"
      vetoed = phi_share_body(build_tuple_store_module, "phi_tuple_store", veto: true)
      vetoed.should_not contain("phi_slot")
      ENV["ADAMAS_PHI_SHARE_VETO"]?.should eq("")
      ENV["ADAMAS_PHI_SHARE_VETO_FILTER"]?.should eq("some_other_function")
      ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"]?.should eq("phi_tuple_store")
    ensure
      if previous_veto
        ENV["ADAMAS_PHI_SHARE_VETO"] = previous_veto
      else
        ENV.delete("ADAMAS_PHI_SHARE_VETO")
      end
      if previous_filter
        ENV["ADAMAS_PHI_SHARE_VETO_FILTER"] = previous_filter
      else
        ENV.delete("ADAMAS_PHI_SHARE_VETO_FILTER")
      end
      if previous_legacy
        ENV["ADAMAS_PHI_SHARE_LEGACY_FILTER"] = previous_legacy
      else
        ENV.delete("ADAMAS_PHI_SHARE_LEGACY_FILTER")
      end
    end
  end
end
