require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_exact_shadow_precanonical_occurrences : Array(Tuple(UInt64, BlockId, ValueId, String))
    missing_incremental_precanonical_occurrences.map do |occurrence|
      {
        occurrence.function_identity,
        occurrence.block_id,
        occurrence.call_id,
        occurrence.raw_name,
      }
    end
  end

  def __test_exact_shadow_select_batch(
    missing : Array(String),
    budget : Int32,
  ) : {Array(String), Bool}
    select_missing_call_target_batch(missing, budget)
  end

  def __test_exact_shadow_refresh_segments(
    cached : Hash(UInt64, Array(String)),
    order : Array(UInt64),
    current : Hash(UInt64, Array(String)),
  ) : {Array(Array(String)), Int32}
    missing_incremental_refresh_segments(cached, order, current)
  end

  def __test_exact_shadow_flatten_segments(
    segments : Array(Array(String)),
  ) : Array(String)
    missing_incremental_flatten_segments(segments)
  end

  def __test_exact_shadow_target_certificate(
    name : String,
    queued_names : Array(String),
  ) : {Bool, String, Bool}
    queued = Set(String).new(queued_names.size)
    queued_names.each { |queued_name| queued.add(queued_name) }
    certificate = missing_incremental_target_certificate(name, queued)
    {
      certificate.body_present,
      certificate.state.to_s,
      certificate.queued,
    }
  end

  def __test_exact_shadow_target_certificate_names(
    demands : Array(String),
    queued_names : Array(String),
  ) : Array(String)
    queued = Set(String).new(queued_names.size)
    queued_names.each { |queued_name| queued.add(queued_name) }
    missing_incremental_queue_snapshot_target_certificates(demands, queued)
      .keys
      .sort
  end

  def __test_exact_shadow_set_target_state(
    name : String,
    state : String,
  ) : Nil
    @function_lowering_states[name] = case state
                                      when "pending"
                                        FunctionLoweringState::Pending
                                      when "in_progress"
                                        FunctionLoweringState::InProgress
                                      when "completed"
                                        FunctionLoweringState::Completed
                                      else
                                        FunctionLoweringState::NotStarted
                                      end
  end

  def __test_exact_shadow_lower_missing_with_budget(budget : Int32) : Nil
    previous = ENV["ADAMAS_MISSING_BUDGET"]?
    ENV["ADAMAS_MISSING_BUDGET"] = budget.to_s
    lower_missing_call_targets
  ensure
    if previous
      ENV["ADAMAS_MISSING_BUDGET"] = previous
    else
      ENV.delete("ADAMAS_MISSING_BUDGET")
    end
  end

  def __test_exact_shadow_function_def_names(base_name : String) : Array(String)
    @function_defs.keys.select do |name|
      name == base_name || name.starts_with?("#{base_name}$")
    end
  end

  def __test_exact_shadow_revision_certificate(
    func : Adamas::HIR::Function,
  ) : {UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64}
    certificate = missing_incremental_revision_certificate(func)
    {
      certificate.function_set_revision,
      certificate.hir_body_revision,
      certificate.function_def_revision,
      certificate.lowering_state_revision,
      certificate.pending_queue_revision,
      certificate.function_body_revision,
      certificate.function_demand_revision,
      certificate.function_type_revision,
    }
  end

  def __test_exact_shadow_set_owned_state(
    name : String,
    state : FunctionLoweringState,
  ) : Nil
    set_function_state(name, state)
  end

  def __test_exact_shadow_enqueue_owned(name : String) : Nil
    enqueue_pending_function(name)
  end

  def __test_exact_shadow_set_function_type(
    name : String,
    return_type : Adamas::HIR::TypeRef,
  ) : Bool
    set_function_type_entry(name, return_type)
  end

  def __test_exact_shadow_rewrite_hash_call(
    func : Adamas::HIR::Function,
    block : Adamas::HIR::Block,
    index : Int32,
    call : Adamas::HIR::Call,
  ) : Bool
    rewrite_hash_do_compaction_default_call(func, block, index, call)
  end

  def __test_exact_shadow_revision_compare(
    func : Adamas::HIR::Function,
    cached_name : String,
    current_name : String,
    mutate_during_scan : Bool,
  ) : {Int32, Int32, Int32, Int32}
    function_identity = func.id.to_u64
    before_certificate = missing_incremental_revision_certificate(func)
    previous = {
      function_identity => before_certificate,
    }
    before_scan = {
      function_identity => before_certificate,
    }
    if mutate_during_scan
      func.get_block(func.entry_block).add(
        Adamas::HIR::Literal.new(
          func.next_value_id,
          Adamas::HIR::TypeRef::INT32,
          1_i64,
        )
      )
    end
    after_scan = {
      function_identity => missing_incremental_revision_certificate(func),
    }
    cached_raw = {
      function_identity => [cached_name],
    }
    cached_available = {
      function_identity => [cached_name],
    }
    current_raw = {
      function_identity => [current_name],
    }
    current_available = {
      function_identity => [current_name],
    }

    missing_incremental_revision_compare(
      previous,
      before_scan,
      after_scan,
      cached_raw,
      cached_available,
      current_raw,
      current_available,
    )
  end

  def __test_exact_shadow_union_materialization_revision_compare(
    func : Adamas::HIR::Function,
    union_name : String,
    method_name : String,
    target_name : String,
  )
    function_identity = func.id.to_u64
    before_target_body = @module.has_function_with_body?(target_name)
    before_certificate = missing_incremental_revision_certificate(func)
    previous = {
      function_identity => before_certificate,
    }
    before_scan = {
      function_identity => before_certificate,
    }
    resolved_name = resolve_union_method_call(
      union_name,
      method_name,
      [] of Adamas::HIR::TypeRef,
      false,
    )
    after_target_body = @module.has_function_with_body?(target_name)
    after_scan = {
      function_identity => missing_incremental_revision_certificate(func),
    }
    cached_raw = {
      function_identity => [target_name],
    }
    current_raw = {
      function_identity => [target_name],
    }
    cached_available = {
      function_identity => (before_target_body ? [] of String : [target_name]),
    }
    current_available = {
      function_identity => (after_target_body ? [] of String : [target_name]),
    }

    full_compare = missing_incremental_revision_compare(
      previous,
      before_scan,
      after_scan,
      cached_raw,
      cached_available,
      current_raw,
      current_available,
    )
    raw_compare = missing_incremental_raw_local_compare(
      previous,
      before_scan,
      after_scan,
      cached_raw,
      cached_available,
      current_raw,
      current_available,
    )
    {
      resolved_name,
      before_target_body,
      after_target_body,
      full_compare,
      raw_compare,
      cached_available != current_available,
    }
  end

  def __test_exact_shadow_raw_local_compare(
    func : Adamas::HIR::Function,
    cached_name : String,
    current_name : String,
    mutate_during_scan : Bool,
  ) : {Int32, Int32, Int32, Int32, Int32}
    function_identity = func.id.to_u64
    before_certificate = missing_incremental_revision_certificate(func)
    previous = {
      function_identity => before_certificate,
    }
    before_scan = {
      function_identity => before_certificate,
    }
    if mutate_during_scan
      func.get_block(func.entry_block).add(
        Adamas::HIR::Literal.new(
          func.next_value_id,
          Adamas::HIR::TypeRef::INT32,
          1_i64,
        )
      )
    end
    after_scan = {
      function_identity => missing_incremental_revision_certificate(func),
    }
    cached_raw = {
      function_identity => [cached_name],
    }
    current_raw = {
      function_identity => [current_name],
    }
    cached_available = {
      function_identity => [] of String,
    }
    current_available = {
      function_identity => [] of String,
    }

    missing_incremental_raw_local_compare(
      previous,
      before_scan,
      after_scan,
      cached_raw,
      cached_available,
      current_raw,
      current_available,
    )
  end

  def __test_exact_shadow_raw_local_public_call_bypass(
    func : Adamas::HIR::Function,
    call : Adamas::HIR::Call,
    rewritten_name : String,
  ) : {Int32, Int32, Int32, Int32, Int32}
    function_identity = func.id.to_u64
    cached_name = call.method_name
    before_certificate = missing_incremental_revision_certificate(func)
    previous = {
      function_identity => before_certificate,
    }
    before_scan = {
      function_identity => before_certificate,
    }
    call.method_name = rewritten_name
    after_scan = {
      function_identity => missing_incremental_revision_certificate(func),
    }
    empty_available = {
      function_identity => [] of String,
    }

    missing_incremental_raw_local_compare(
      previous,
      before_scan,
      after_scan,
      {function_identity => [cached_name]},
      empty_available,
      {function_identity => [rewritten_name]},
      empty_available,
    )
  end

  def __test_exact_shadow_availability_replay_intervening_target_mutation(
    func : Adamas::HIR::Function,
    target : Adamas::HIR::Function,
  ) : {Array(String), Array(String), {Int32, Int32, Int32, Int32}}
    function_identity = func.id.to_u64
    target_name = target.name
    before_certificate = missing_incremental_revision_certificate(func)
    previous = {
      function_identity => before_certificate,
    }
    before_scan = {
      function_identity => before_certificate,
    }
    queued_names = Set(String).new
    target_certificates = missing_incremental_target_certificates(
      [target_name],
      queued_names,
    )
    replay_available = {
      function_identity => missing_incremental_replay_available_segment(
        [target_name],
        target_certificates,
      ),
    }

    target.get_block(target.entry_block).add(
      Adamas::HIR::Literal.new(
        target.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        1_i64,
      )
    )
    after_scan = {
      function_identity => missing_incremental_revision_certificate(func),
    }
    current_available = {
      function_identity => [] of String,
    }
    compare = missing_incremental_availability_replay_compare(
      previous,
      before_scan,
      after_scan,
      replay_available,
      current_available,
    )

    {
      replay_available[function_identity],
      current_available[function_identity],
      compare,
    }
  end

  def __test_exact_shadow_demand_provenance
    stable_source = @module.create_function(
      "Owner#stable_provenance_source",
      Adamas::HIR::TypeRef::VOID,
    )
    changed_source = @module.create_function(
      "Owner#changed_provenance_source",
      Adamas::HIR::TypeRef::VOID,
    )
    scan_invalidated_source = @module.create_function(
      "Owner#scan_invalidated_provenance_source",
      Adamas::HIR::TypeRef::VOID,
    )
    previous = {
      stable_source.id.to_u64           => missing_incremental_revision_certificate(stable_source),
      changed_source.id.to_u64          => missing_incremental_revision_certificate(changed_source),
      scan_invalidated_source.id.to_u64 => missing_incremental_revision_certificate(scan_invalidated_source),
    }

    changed_source.get_block(changed_source.entry_block).add(
      Adamas::HIR::Literal.new(
        changed_source.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        1_i64,
      )
    )
    new_source = @module.create_function(
      "Owner#new_provenance_source",
      Adamas::HIR::TypeRef::VOID,
    )
    before_scan = {
      stable_source.id.to_u64           => missing_incremental_revision_certificate(stable_source),
      changed_source.id.to_u64          => missing_incremental_revision_certificate(changed_source),
      scan_invalidated_source.id.to_u64 => missing_incremental_revision_certificate(scan_invalidated_source),
      new_source.id.to_u64              => missing_incremental_revision_certificate(new_source),
    }

    scan_invalidated_source.get_block(scan_invalidated_source.entry_block).add(
      Adamas::HIR::Literal.new(
        scan_invalidated_source.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        2_i64,
      )
    )
    after_scan = {
      stable_source.id.to_u64           => missing_incremental_revision_certificate(stable_source),
      changed_source.id.to_u64          => missing_incremental_revision_certificate(changed_source),
      scan_invalidated_source.id.to_u64 => missing_incremental_revision_certificate(scan_invalidated_source),
      new_source.id.to_u64              => missing_incremental_revision_certificate(new_source),
    }
    current_available = {
      stable_source.id.to_u64           => ["stable_prior", "mixed_prior", "stable_new_only"],
      changed_source.id.to_u64          => ["changed_prior", "mixed_prior"],
      scan_invalidated_source.id.to_u64 => ["scan_prior"],
      new_source.id.to_u64              => ["new_only"],
    }
    queued_names = Set{
      "stable_prior",
      "mixed_prior",
      "changed_prior",
      "scan_prior",
    }
    previous_targets = missing_incremental_target_certificates(
      queued_names.to_a,
      queued_names,
    )

    missing_incremental_demand_provenance(
      previous,
      before_scan,
      after_scan,
      current_available,
      previous_targets,
    )
  end
end

private def parse_exact_shadow_source(code : String) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

private def exact_shadow_converter : Adamas::HIR::AstToHir
  Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
end

describe "missing-call exact incremental shadow" do
  it "captures immutable pre-canonical call identity and order without resolving calls" do
    converter = exact_shadow_converter
    target = converter.module.create_function(
      "Owner#precanonical_target",
      Adamas::HIR::TypeRef::INT32,
    )
    demand_first = converter.module.create_function(
      "Owner#precanonical_demand_first",
      Adamas::HIR::TypeRef::VOID,
    )
    demand_block = demand_first.get_block(demand_first.entry_block)
    direct_call = Adamas::HIR::Call.new(
      demand_first.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      target.name,
    )
    materializer_call = Adamas::HIR::Call.new(
      demand_first.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      "Nil | Owner#precanonical_target",
    )
    demand_block.add(direct_call)
    demand_block.add(materializer_call)

    materializer_first = converter.module.create_function(
      "Owner#precanonical_materializer_first",
      Adamas::HIR::TypeRef::VOID,
    )
    materializer_block = materializer_first.get_block(materializer_first.entry_block)
    reverse_materializer = Adamas::HIR::Call.new(
      materializer_first.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      "Nil | Owner#precanonical_target",
    )
    reverse_direct = Adamas::HIR::Call.new(
      materializer_first.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      target.name,
    )
    materializer_block.add(reverse_materializer)
    materializer_block.add(reverse_direct)

    converter.module.has_function_with_body?(target.name).should be_false
    before_demand_revision =
      converter.__test_exact_shadow_revision_certificate(demand_first)[6]
    occurrences = converter.__test_exact_shadow_precanonical_occurrences
    occurrences.select { |entry| entry[0] == demand_first.id.to_u64 }.should eq([
      {demand_first.id.to_u64, demand_block.id, direct_call.id, target.name},
      {demand_first.id.to_u64, demand_block.id, materializer_call.id, "Nil | Owner#precanonical_target"},
    ])
    occurrences.select { |entry| entry[0] == materializer_first.id.to_u64 }.should eq([
      {materializer_first.id.to_u64, materializer_block.id, reverse_materializer.id, "Nil | Owner#precanonical_target"},
      {materializer_first.id.to_u64, materializer_block.id, reverse_direct.id, target.name},
    ])

    demand_first.rewrite_call_method_name(materializer_call, target.name)
    late_call = Adamas::HIR::Call.new(
      demand_first.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      "Owner#precanonical_late",
    )
    demand_block.add(late_call)
    occurrences.select { |entry| entry[0] == demand_first.id.to_u64 }.map(&.[3])
      .should eq([target.name, "Nil | Owner#precanonical_target"])
    converter.__test_exact_shadow_precanonical_occurrences
      .select { |entry| entry[0] == demand_first.id.to_u64 }
      .map(&.[3])
      .should eq([target.name, target.name, late_call.method_name])
    converter.__test_exact_shadow_revision_certificate(demand_first)[6]
      .should be > before_demand_revision
    converter.module.has_function_with_body?(target.name).should be_false
  end

  it "retains raw and occurrence-admitted demands in full-scan order" do
    converter = exact_shadow_converter
    cached = {
      1_u64 => ["stale"],
      3_u64 => ["removed"],
    }
    current = {
      1_u64 => ["carry", "done"],
      2_u64 => ["new", "carry", "materialized"],
    }
    current_available = {
      1_u64 => ["carry", "done"],
      2_u64 => ["new", "carry"],
    }

    raw_segments, raw_changed = converter.__test_exact_shadow_refresh_segments(
      cached,
      [1_u64, 2_u64],
      current,
    )
    raw_changed.should eq(3)
    cached.keys.sort.should eq([1_u64, 2_u64])
    converter.__test_exact_shadow_flatten_segments(raw_segments)
      .should eq(["carry", "done", "new", "materialized"])

    available_segments, available_changed =
      converter.__test_exact_shadow_refresh_segments(
        Hash(UInt64, Array(String)).new,
        [1_u64, 2_u64],
        current_available,
      )
    available_changed.should eq(2)
    available =
      converter.__test_exact_shadow_flatten_segments(available_segments)
    available.should eq(["carry", "done", "new"])
    converter.__test_exact_shadow_select_batch(available, 1)
      .should eq({["carry"], true})
  end

  it "preserves occurrence admission when the target changes later" do
    converter = exact_shadow_converter
    target_name = "late_available"
    admitted_segments, changed =
      converter.__test_exact_shadow_refresh_segments(
        Hash(UInt64, Array(String)).new,
        [1_u64],
        {1_u64 => [target_name]},
      )
    changed.should eq(1)

    target = converter.module.create_function(
      target_name,
      Adamas::HIR::TypeRef::VOID,
    )
    target.get_block(target.entry_block).add(
      Adamas::HIR::Literal.new(
        target.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        1_i64,
      )
    )

    converter.__test_exact_shadow_flatten_segments(admitted_segments)
      .should eq([target_name])
    converter.__test_exact_shadow_target_certificate(target_name, [] of String)
      .should eq({true, "NotStarted", false})
    converter.__test_exact_shadow_target_certificate(target_name, [target_name])
      .should eq({true, "NotStarted", true})

    first_id = target.id
    converter.module.remove_function(target_name).should be_true
    replacement = converter.module.create_function(
      target_name,
      Adamas::HIR::TypeRef::VOID,
    )
    replacement.id.should_not eq(first_id)

    converter.__test_exact_shadow_set_target_state(target_name, "pending")
    converter.__test_exact_shadow_target_certificate(target_name, [target_name])
      .should eq({false, "Pending", true})
    converter.__test_exact_shadow_set_target_state(target_name, "in_progress")
    converter.__test_exact_shadow_target_certificate(target_name, [target_name])
      .should eq({false, "InProgress", true})
  end

  it "retains queued bodyless targets that were not emitted by the prior scan" do
    converter = exact_shadow_converter

    converter.__test_exact_shadow_target_certificate_names(
      ["demanded"],
      ["queued_elsewhere"],
    ).should eq(["demanded", "queued_elsewhere"])
  end

  it "selects the exact legacy bounded and unlimited prefixes" do
    converter = exact_shadow_converter
    demands = ["stuck", "next", "later"]

    converter.__test_exact_shadow_select_batch(demands, 1)
      .should eq({["stuck"], true})
    converter.__test_exact_shadow_select_batch(demands, 0)
      .should eq({demands, false})
  end

  it "reuses exact segments while honoring function order and mutation" do
    converter = exact_shadow_converter
    cached = {
      1_u64 => ["first"],
      2_u64 => ["second"],
    }
    current = {
      1_u64 => ["first"],
      2_u64 => ["second"],
    }

    segments, changed = converter.__test_exact_shadow_refresh_segments(
      cached,
      [2_u64, 1_u64],
      current,
    )
    changed.should eq(0)
    converter.__test_exact_shadow_flatten_segments(segments)
      .should eq(["second", "first"])

    current[2_u64] = ["second", "late_missing_target"]
    segments, changed = converter.__test_exact_shadow_refresh_segments(
      cached,
      [2_u64, 1_u64],
      current,
    )
    changed.should eq(1)
    converter.__test_exact_shadow_flatten_segments(segments)
      .should eq(["second", "late_missing_target", "first"])
  end

  it "keeps the legacy no-progress stop with the shadow off or on" do
    source = "def concrete_tail; 1; end"
    arena, roots = parse_exact_shadow_source(source)
    converter = Adamas::HIR::AstToHir.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => source},
    )
    converter.arena = arena

    def_node = roots.compact_map do |expr_id|
      arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
    end.first
    converter.register_function(def_node)
    target_name =
      converter.__test_exact_shadow_function_def_names("concrete_tail").first?
    raise "No registered concrete_tail target" unless target_name

    converter.module.create_function(target_name, Adamas::HIR::TypeRef::INT32)
    driver = converter.module.create_function(
      "__test_missing_budget_driver",
      Adamas::HIR::TypeRef::VOID,
    )
    block = driver.get_block(driver.entry_block)
    34.times do |index|
      block.add(
        Adamas::HIR::Call.without_receiver(
          driver.next_value_id,
          Adamas::HIR::TypeRef::VOID,
          "missing_budget_head_#{index}",
          [] of Adamas::HIR::ValueId,
        )
      )
    end
    block.add(
      Adamas::HIR::Call.without_receiver(
        driver.next_value_id,
        Adamas::HIR::TypeRef::INT32,
        target_name,
        [] of Adamas::HIR::ValueId,
      )
    )

    previous_falsifier = ENV["ADAMAS_MISSING_INCREMENTAL_FALSIFIER"]?
    begin
      ENV.delete("ADAMAS_MISSING_INCREMENTAL_FALSIFIER")
      converter.__test_exact_shadow_lower_missing_with_budget(34)
      converter.module.has_function_with_body?(target_name).should be_false

      ENV["ADAMAS_MISSING_INCREMENTAL_FALSIFIER"] = "1"
      converter.__test_exact_shadow_lower_missing_with_budget(34)
      converter.module.has_function_with_body?(target_name).should be_false
    ensure
      if previous_falsifier
        ENV["ADAMAS_MISSING_INCREMENTAL_FALSIFIER"] = previous_falsifier
      else
        ENV.delete("ADAMAS_MISSING_INCREMENTAL_FALSIFIER")
      end
    end
  end

  it "invalidates the revision certificate at every mutation owner" do
    converter = exact_shadow_converter
    function = converter.module.create_function(
      "Owner#revision_driver",
      Adamas::HIR::TypeRef::VOID,
    )
    block = function.get_block(function.entry_block)
    baseline = converter.__test_exact_shadow_revision_certificate(function)

    call = Adamas::HIR::Call.new(
      function.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      "Owner#first",
    )
    block.add(call)
    after_call = converter.__test_exact_shadow_revision_certificate(function)
    after_call[1].should be > baseline[1]
    after_call[5].should be > baseline[5]
    after_call[6].should be > baseline[6]

    converter.__test_exact_shadow_set_owned_state(
      function.name,
      Adamas::HIR::AstToHir::FunctionLoweringState::Pending,
    )
    after_state = converter.__test_exact_shadow_revision_certificate(function)
    after_state[3].should be > after_call[3]
    converter.__test_exact_shadow_set_owned_state(
      function.name,
      Adamas::HIR::AstToHir::FunctionLoweringState::Pending,
    )
    converter.__test_exact_shadow_revision_certificate(function)[3]
      .should eq(after_state[3])

    converter.__test_exact_shadow_enqueue_owned(function.name)
    after_enqueue = converter.__test_exact_shadow_revision_certificate(function)
    after_enqueue[4].should be > after_state[4]
    converter.__test_exact_shadow_enqueue_owned(function.name)
    converter.__test_exact_shadow_revision_certificate(function)[4]
      .should be > after_enqueue[4]
  end

  it "rejects same-scan reuse after the Hash call rewrite mutates HIR" do
    converter = exact_shadow_converter
    function = converter.module.create_function(
      "Owner#hash_revision_driver",
      Adamas::HIR::TypeRef::VOID,
    )
    block = function.get_block(function.entry_block)
    call = Adamas::HIR::Call.new(
      function.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      "Hash(String,Int32)#do_compaction",
    )
    block.add(call)
    before = converter.__test_exact_shadow_revision_certificate(function)

    converter.__test_exact_shadow_rewrite_hash_call(
      function,
      block,
      0,
      call,
    ).should be_true
    after_rewrite =
      converter.__test_exact_shadow_revision_certificate(function)

    block.instructions.size.should eq(2)
    call.args.size.should eq(1)
    call.method_name.should_not eq("Hash(String,Int32)#do_compaction")
    after_rewrite[1].should be > before[1]
    after_rewrite[5].should be > before[5]
    after_rewrite[6].should be > before[6]
  end

  it "bumps the function-def revision only for semantic registry changes" do
    source = "def revision_target; 1; end"
    arena, roots = parse_exact_shadow_source(source)
    converter = Adamas::HIR::AstToHir.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => source},
    )
    converter.arena = arena
    probe = converter.module.create_function(
      "Owner#def_revision_probe",
      Adamas::HIR::TypeRef::VOID,
    )
    before = converter.__test_exact_shadow_revision_certificate(probe)
    def_node = roots.compact_map do |expr_id|
      arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
    end.first

    converter.register_function(def_node)
    after_register =
      converter.__test_exact_shadow_revision_certificate(probe)
    after_register[2].should be > before[2]

    converter.register_function(def_node)
    converter.__test_exact_shadow_revision_certificate(probe)[2]
      .should eq(after_register[2])
  end

  it "bumps the function-type revision only for semantic changes" do
    converter = exact_shadow_converter
    function = converter.module.create_function(
      "Owner#type_revision_probe",
      Adamas::HIR::TypeRef::VOID,
    )
    before = converter.__test_exact_shadow_revision_certificate(function)

    converter.__test_exact_shadow_set_function_type(
      function.name,
      Adamas::HIR::TypeRef::INT32,
    ).should be_true
    after_update =
      converter.__test_exact_shadow_revision_certificate(function)
    after_update[7].should be > before[7]

    converter.__test_exact_shadow_set_function_type(
      function.name,
      Adamas::HIR::TypeRef::INT32,
    ).should be_false
    converter.__test_exact_shadow_revision_certificate(function)[7]
      .should eq(after_update[7])
  end

  it "distinguishes stable reuse, false reuse, and scan invalidation" do
    converter = exact_shadow_converter
    stable = converter.module.create_function(
      "Owner#stable_revision_probe",
      Adamas::HIR::TypeRef::VOID,
    )
    converter.__test_exact_shadow_revision_compare(
      stable,
      "Owner#target",
      "Owner#target",
      false,
    ).should eq({1, 1, 0, 0})

    false_reuse = converter.module.create_function(
      "Owner#false_reuse_probe",
      Adamas::HIR::TypeRef::VOID,
    )
    converter.__test_exact_shadow_revision_compare(
      false_reuse,
      "Owner#old",
      "Owner#new",
      false,
    ).should eq({1, 1, 0, 1})

    scan_mutation = converter.module.create_function(
      "Owner#scan_mutation_probe",
      Adamas::HIR::TypeRef::VOID,
    )
    converter.__test_exact_shadow_revision_compare(
      scan_mutation,
      "Owner#old",
      "Owner#new",
      true,
    ).should eq({1, 0, 1, 0})
  end

  it "attributes unique missing targets to source revision and prior queue state" do
    converter = exact_shadow_converter

    converter.__test_exact_shadow_demand_provenance.should eq({
      occurrences:                                        7,
      stable_occurrences:                                 4,
      new_or_changed_occurrences:                         3,
      scan_invalidated_occurrences:                       1,
      prior_queued_bodyless_occurrences:                  5,
      stable_prior_queued_bodyless_occurrences:           3,
      new_or_changed_prior_queued_bodyless_occurrences:   2,
      scan_invalidated_prior_queued_bodyless_occurrences: 1,
      targets:                                            6,
      stable_targets:                                     4,
      new_or_changed_targets:                             3,
      scan_invalidated_targets:                           1,
      stable_and_new_or_changed_targets:                  1,
      prior_queued_bodyless_targets:                      4,
      stable_prior_queued_bodyless_targets:               3,
      new_or_changed_prior_queued_bodyless_targets:       2,
      scan_invalidated_prior_queued_bodyless_targets:     1,
    })
  end

  it "separates raw stability from later same-scan union accessor materialization" do
    source = <<-CRYSTAL
      class Outer
        class Info
          property kind : FileType
        end
      end

      enum FileType
        Other
        Tuple
      end
    CRYSTAL
    arena, roots = parse_exact_shadow_source(source)
    converter = Adamas::HIR::AstToHir.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => source},
    )
    converter.arena = arena
    outer_expr = roots.find do |expr_id|
      node = arena[expr_id]
      node.is_a?(Adamas::Compiler::Frontend::ClassNode) &&
        String.new(
          node.as(Adamas::Compiler::Frontend::ClassNode).name.not_nil!,
        ) == "Outer"
    end
    enum_expr = roots.find do |expr_id|
      arena[expr_id].is_a?(Adamas::Compiler::Frontend::EnumNode)
    end
    converter.register_class(
      arena[outer_expr.not_nil!].as(Adamas::Compiler::Frontend::ClassNode),
    )
    converter.register_enum(
      arena[enum_expr.not_nil!].as(Adamas::Compiler::Frontend::EnumNode),
    )

    target_name = "Outer::Info#kind"
    driver = converter.module.create_function(
      "Owner#same_scan_driver",
      Adamas::HIR::TypeRef::VOID,
    )
    driver.get_block(driver.entry_block).add(
      Adamas::HIR::Call.new(
        driver.next_value_id,
        Adamas::HIR::TypeRef::VOID,
        target_name,
      )
    )

    resolved_name,
      before_target_body,
      after_target_body,
      full_compare,
      raw_compare,
      availability_changed =
        converter.__test_exact_shadow_union_materialization_revision_compare(
          driver,
          "Nil | Outer::Info",
          "kind",
          target_name,
        )

    resolved_name.should eq(target_name)
    before_target_body.should be_false
    after_target_body.should be_true
    full_compare.should eq({1, 0, 1, 0})
    raw_compare.should eq({1, 1, 0, 0, 1})
    availability_changed.should be_true
  end

  it "detects raw false reuse and local scan mutation" do
    converter = exact_shadow_converter
    stable = converter.module.create_function(
      "Owner#raw_stable_revision_probe",
      Adamas::HIR::TypeRef::VOID,
    )
    converter.__test_exact_shadow_raw_local_compare(
      stable,
      "Owner#target",
      "Owner#target",
      false,
    ).should eq({1, 1, 0, 0, 0})

    false_reuse = converter.module.create_function(
      "Owner#raw_false_reuse_probe",
      Adamas::HIR::TypeRef::VOID,
    )
    converter.__test_exact_shadow_raw_local_compare(
      false_reuse,
      "Owner#old",
      "Owner#new",
      false,
    ).should eq({1, 1, 0, 1, 0})

    scan_mutation = converter.module.create_function(
      "Owner#raw_scan_mutation_probe",
      Adamas::HIR::TypeRef::VOID,
    )
    converter.__test_exact_shadow_raw_local_compare(
      scan_mutation,
      "Owner#old",
      "Owner#new",
      true,
    ).should eq({1, 0, 1, 0, 0})
  end

  it "detects a public Call mutation that bypasses the owner ledger" do
    converter = exact_shadow_converter
    function = converter.module.create_function(
      "Owner#raw_public_bypass_probe",
      Adamas::HIR::TypeRef::VOID,
    )
    call = Adamas::HIR::Call.new(
      function.next_value_id,
      Adamas::HIR::TypeRef::VOID,
      "Owner#before",
    )
    function.get_block(function.entry_block).add(call)

    converter.__test_exact_shadow_raw_local_public_call_bypass(
      function,
      call,
      "Owner#after",
    ).should eq({1, 1, 0, 1, 0})
  end

  it "rejects a pre-scan target snapshot after an intervening materialization" do
    converter = exact_shadow_converter
    target = converter.module.create_function(
      "Owner#availability_replay_target",
      Adamas::HIR::TypeRef::INT32,
    )
    observer = converter.module.create_function(
      "Owner#availability_replay_observer",
      Adamas::HIR::TypeRef::VOID,
    )

    replay_available,
      current_available,
      compare =
        converter.__test_exact_shadow_availability_replay_intervening_target_mutation(
          observer,
          target,
        )

    replay_available.should eq([target.name])
    current_available.should be_empty
    compare.should eq({1, 1, 1, 1})
  end
end
