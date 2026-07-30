require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
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
end
