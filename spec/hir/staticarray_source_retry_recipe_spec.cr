require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private record StaticArrayRetryReceipt,
  name : String,
  refused : Array(String),
  dependencies : Array(String),
  replay_present : Bool,
  exact_source_present : Bool,
  exact_source_current : Bool,
  replay_current : Bool,
  replay_same_source : Bool,
  callshape_empty : Bool,
  required_arg_sibling_present : Bool,
  required_arg_sibling_name : String?,
  required_arg_sibling_same_owner : Bool,
  selected_source_is_nilary : Bool,
  stale_def_rejected : Bool,
  stale_arena_rejected : Bool

class Adamas::HIR::AstToHir
  def spec_replay_recipe_type_ref(name : String) : TypeRef
    type_ref_for_name(name)
  end

  def spec_capture_depth_two_source_retry(
    consumer_name : String,
    arg_types : Array(TypeRef),
    producer_name : String,
  ) : Tuple(Bool, Array(StaticArrayRetryReceipt))
    target = mangle_function_name(consumer_name, arg_types)
    producer = mangle_function_name(producer_name, [] of TypeRef)
    producer_body_before = @module.has_function_with_body?(producer)
    remember_callsite_arg_types(target, arg_types)

    saved_depth = @force_lower_return_type_depth
    saved_driver = @force_lower_retry_driver_active
    saved_inline_function = @inline_yield_function_depth
    saved_inline_block = @inline_yield_block_body_depth
    saved_inline_proc = @inline_yield_proc_depth
    saved_inline_names = @inline_yield_name_stack
    @force_lower_return_type_depth = 0
    # The failing LavinMQ chain is entered from an inline-yield body. This
    # creates the same depth-two yield-free demand without compiling a generic
    # stock prelude in this focused HIR probe.
    @inline_yield_block_body_depth = 1
    # Pause only the retry driver so its exact receipt can be inspected.
    @force_lower_retry_driver_active = true

    begin
      force_lower_function_for_return_type(target, bypass_inline_yield: true)
      observations = [] of StaticArrayRetryReceipt
      @force_lower_retry_work.each do |work|
        case work
        when ForceLowerRetryRequest
          next unless work.name.ends_with?("#to_slice")
          dependencies = (@force_lower_provisional_dependencies[work.name]? || Set(String).new).to_a.sort
          exact = work.exact_source
          replay = work.replay_callsite
          source_current = exact ? force_lower_exact_source_matches?(work.name, exact) : false
          replay_current = replay ? force_lower_replay_callsite_current?(work.name, replay) : false
          replay_same_source = if replay && exact
                                 replay.source_def.same?(exact.source_def) &&
                                   replay.source_arena.same?(exact.source_arena) &&
                                   replay.source_registry_name == exact.source_registry_name
                               else
                                 false
                               end
          callshape_empty = if replay
                              callsite = replay.callsite
                              callsite.types.empty? &&
                                (callsite.literals.try(&.empty?) != false) &&
                                (callsite.enum_names.try(&.empty?) != false) &&
                                !callsite.has_block && !callsite.has_named_args &&
                                (callsite.named_arg_names.try(&.empty?) != false) &&
                                (callsite.source_argument_facts.try(&.empty?) != false)
                            else
                              false
                            end
          selected_source_is_nilary = exact ? exact.source_def.params.try(&.empty?) != false : false
          sibling = nil.as(Tuple(String, Adamas::Compiler::Frontend::DefNode)?)
          sibling_same_owner = false
          if exact
            selected_registry_name = exact.source_registry_name || work.name
            selected_owner = method_owner(selected_registry_name)
            selected_base = strip_type_suffix(selected_registry_name)
            @function_defs.each do |candidate_name, candidate_def|
              next unless method_owner(candidate_name) == selected_owner
              next unless strip_type_suffix(candidate_name) == selected_base
              next if candidate_def.same?(exact.source_def)
              next unless candidate_def.params.try(&.size) == 1
              sibling = {candidate_name, candidate_def}
              sibling_same_owner = true
              break
            end
          end
          stale_def_rejected = false
          stale_arena_rejected = false
          if exact && (sibling_entry = sibling) && (registry_name = exact.source_registry_name || work.name)
            if original = @function_defs[registry_name]?
              @function_defs[registry_name] = sibling_entry[1]
              stale_def_rejected = !force_lower_retry_source_current?(work)
              @function_defs[registry_name] = original
            end
            if original_arena = @function_def_arenas[registry_name]?
              decoy_parser = Adamas::Compiler::Frontend::Parser.new(
                Adamas::Compiler::Frontend::Lexer.new("class ReplayForeignArena; end"),
              )
              decoy_arena = decoy_parser.parse_program.arena
              @function_def_arenas[registry_name] = decoy_arena
              stale_arena_rejected = !force_lower_retry_source_current?(work)
              @function_def_arenas[registry_name] = original_arena
            end
          end
          observations << StaticArrayRetryReceipt.new(
            work.name,
            work.refused.dup.sort,
            dependencies,
            !replay.nil?,
            !exact.nil?,
            source_current,
            replay_current,
            replay_same_source,
            callshape_empty,
            !sibling.nil?,
            sibling.try(&.[0]),
            sibling_same_owner,
            selected_source_is_nilary,
            stale_def_rejected,
            stale_arena_rejected,
          )
        end
      end
      {producer_body_before, observations}
    ensure
      @force_lower_retry_work.clear
      @force_lower_retry_driver_active = saved_driver
      @force_lower_return_type_depth = saved_depth
      @inline_yield_function_depth = saved_inline_function
      @inline_yield_block_body_depth = saved_inline_block
      @inline_yield_proc_depth = saved_inline_proc
      @inline_yield_name_stack = saved_inline_names
    end
  end
end

private def replay_recipe_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class ReplayStaticArray(T, N)
      def to_unsafe : Int32
        1
      end

      def size : Int32
        N
      end

      def to_slice : Int32
        to_unsafe + size
      end

      def to_slice(flag : Bool) : Int32
        flag ? 2 : 3
      end
    end

    class ReplayStaticArrayConsumer
      def self.consume_bare(value : ReplayStaticArray(Int32, 20)) : Int32
        value.to_slice
      end

      def self.consume_parenthesized(value : ReplayStaticArray(Int32, 20)) : Int32
        value.to_slice()
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter
end

describe "annotated generic nilary source replay recipe" do
  it "retains the authenticated empty callshape after depth-two child refusals" do
    converter = replay_recipe_converter
    owner_type = converter.spec_replay_recipe_type_ref("ReplayStaticArray(Int32, 20)")
    before, observations = converter.spec_capture_depth_two_source_retry(
      "ReplayStaticArrayConsumer.consume_bare",
      [owner_type],
      "ReplayStaticArray(Int32, 20)#to_slice",
    )

    # Registration alone must not pre-materialize the producer, or this probe
    # would pass without crossing the refusal/replay boundary.
    before.should be_false
    retry = observations.find { |event| event.name.ends_with?("#to_slice") }
    retry.should_not be_nil
    event = retry.not_nil!
    event.refused.any? { |name| name.ends_with?("#to_unsafe") }.should be_true
    event.refused.any? { |name| name.ends_with?("#size") }.should be_true
    event.dependencies.any? { |name| name.ends_with?("#to_unsafe") }.should be_true
    event.dependencies.any? { |name| name.ends_with?("#size") }.should be_true
    event.exact_source_present.should be_true
    event.exact_source_current.should be_true
    event.required_arg_sibling_present.should be_true
    event.required_arg_sibling_name.should_not be_nil
    event.required_arg_sibling_same_owner.should be_true
    event.selected_source_is_nilary.should be_true
    event.stale_def_rejected.should be_true
    event.stale_arena_rejected.should be_true

    # Expected to fail on the baseline only after the owner/refusal controls
    # above pass: the bare member path has not published an empty callshape.
    event.replay_present.should be_true
    event.replay_current.should be_true
    event.replay_same_source.should be_true
    event.callshape_empty.should be_true
  end

  it "keeps explicit parentheses as the existing zero-argument control" do
    converter = replay_recipe_converter
    owner_type = converter.spec_replay_recipe_type_ref("ReplayStaticArray(Int32, 20)")
    before, observations = converter.spec_capture_depth_two_source_retry(
      "ReplayStaticArrayConsumer.consume_parenthesized",
      [owner_type],
      "ReplayStaticArray(Int32, 20)#to_slice",
    )
    before.should be_false
    retry = observations.find { |event| event.name.ends_with?("#to_slice") }.not_nil!
    retry.refused.any? { |name| name.ends_with?("#to_unsafe") }.should be_true
    retry.dependencies.any? { |name| name.ends_with?("#size") }.should be_true
    retry.exact_source_current.should be_true
    retry.replay_present.should be_true
    retry.replay_current.should be_true
    retry.replay_same_source.should be_true
    retry.callshape_empty.should be_true
  end
end
