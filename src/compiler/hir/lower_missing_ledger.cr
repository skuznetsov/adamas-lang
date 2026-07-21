# Behavior-neutral bounded telemetry for the HIR lower_missing safety net.
#
# The writer deliberately keeps no AST, HIR, or method-name strings.  Names are
# represented by deterministic FNV-1a identities and are streamed to the
# caller-provided IO while the demand is observed.  The ledger is diagnostic
# only: it never participates in queue admission, target lookup, or lowering.

module Adamas::HIR
  enum LowerMissingDemandContext : UInt8
    Initial = 0
    Final   = 1
  end

  enum LowerMissingDemandReason : UInt8
    CallTarget     = 0
    SuperAlias     = 1
    SuperTarget    = 2
    ModuleFallback = 3
  end

  enum LowerMissingDemandOwnerKind : UInt8
    TopLevel = 0
    Instance = 1
    Class    = 2
    Unknown  = 3
  end

  enum LowerMissingDemandOutcome : UInt8
    Enqueued     = 0
    Materialized = 1
    Deferred     = 2
    StillMissing = 3
    Skipped      = 4
  end

  enum LowerMissingDemandEvent : UInt8
    Demand     = 0
    Summary    = 1
    Checkpoint = 2
  end

  # A compact, deterministic identity for an in-flight method spelling.  This
  # is telemetry only; it is not a semantic or materialization cache key.
  module LowerMissingDemandIdentity
    FNV_OFFSET = 14_695_981_039_346_656_037_u64
    FNV_PRIME  =          1_099_511_628_211_u64

    @[AlwaysInline]
    def self.hash_bytes(text : String, start : Int32 = 0, finish : Int32 = -1) : UInt64
      first = start < 0 ? 0 : start
      last = finish < 0 || finish > text.bytesize ? text.bytesize : finish
      first = last if first > last
      hash = FNV_OFFSET
      bytes = text.to_unsafe
      index = first
      while index < last
        hash ^= bytes[index].to_u64
        hash &*= FNV_PRIME
        index += 1
      end
      hash
    end

    @[AlwaysInline]
    def self.hash_name(name : String) : UInt64
      hash_bytes(name)
    end

    @[AlwaysInline]
    def self.mix_u64(hash : UInt64, value : UInt64) : UInt64
      mixed = hash
      shift = 0
      while shift < 64
        mixed ^= ((value >> shift) & 0xff_u64)
        mixed &*= FNV_PRIME
        shift += 8
      end
      mixed
    end

    @[AlwaysInline]
    def self.owner_kind(name : String) : LowerMissingDemandOwnerKind
      hash_idx = name.rindex('#')
      dot_idx = name.rindex('.')
      if hash_idx && (!dot_idx || hash_idx > dot_idx)
        LowerMissingDemandOwnerKind::Instance
      elsif dot_idx
        LowerMissingDemandOwnerKind::Class
      elsif name.empty?
        LowerMissingDemandOwnerKind::Unknown
      else
        LowerMissingDemandOwnerKind::TopLevel
      end
    end

    @[AlwaysInline]
    def self.owner_identity(name : String) : UInt64
      hash_idx = name.rindex('#')
      dot_idx = name.rindex('.')
      separator = if hash_idx && (!dot_idx || hash_idx > dot_idx)
                    hash_idx
                  elsif dot_idx
                    dot_idx
                  else
                    -1
                  end
      return 0_u64 if separator <= 0

      hash_bytes(name, 0, separator)
    end
  end

  # Numeric-only projection of the already-owned semantic handoff.  Keeping
  # this projection avoids retaining the handoff, its DefInstanceKey, or any
  # semantic interner through the diagnostic path.
  struct LowerMissingDemandHandoffFacts
    getter resolution_id : UInt64
    getter callsite_arena_id : UInt64
    getter callsite_expr_id : Int32
    getter def_arena_id : UInt64
    getter def_expr_id : Int32
    getter receiver_type_id : UInt64
    getter arg_count : Int32
    getter block_type_id : UInt64

    def initialize(@resolution_id : UInt64,
                   @callsite_arena_id : UInt64,
                   @callsite_expr_id : Int32,
                   @def_arena_id : UInt64,
                   @def_expr_id : Int32,
                   @receiver_type_id : UInt64,
                   @arg_count : Int32,
                   @block_type_id : UInt64)
    end

    def self.from(handoff : Adamas::Compiler::Semantic::CallResolutionHandoff) : self
      receiver_id = if receiver = handoff.body_key.receiver_type
                      receiver.id.to_u64
                    else
                      0_u64
                    end
      block_id = if block = handoff.body_key.block_type
                   block.id.to_u64
                 else
                   0_u64
                 end
      new(
        handoff.resolution_id.id,
        handoff.callsite.arena_id,
        handoff.callsite.expr_index,
        handoff.body_key.def_identity.arena_id,
        handoff.body_key.def_identity.expr_index,
        receiver_id,
        handoff.body_key.arg_types.size,
        block_id,
      )
    end
  end

  private struct LowerMissingDemandQueuedFacts
    getter iteration : Int32
    getter context : LowerMissingDemandContext
    getter reason : LowerMissingDemandReason
    getter function_count_before : Int32
    getter pending_before : Int32

    def initialize(@iteration : Int32,
                   @context : LowerMissingDemandContext,
                   @reason : LowerMissingDemandReason,
                   @function_count_before : Int32,
                   @pending_before : Int32)
    end
  end

  private struct LowerMissingDemandShapeFacts
    getter fingerprint : UInt64
    getter mismatch_count : Int32
    getter ambiguous : Bool

    def initialize(@fingerprint : UInt64,
                   @mismatch_count : Int32 = 0,
                   @ambiguous : Bool = false)
    end
  end

  # A streaming writer rather than a retained event graph.  At most `limit`
  # event rows are emitted; additional rows are counted and represented by the
  # final summary.  The default path constructs no instance at all.
  class LowerMissingDemandLedger
    DEFAULT_LIMIT =   4096_i32
    MAX_LIMIT     = 65_536_i32
    HEX_DIGITS    = "0123456789abcdef"

    getter limit : Int32
    getter emitted : Int32
    getter overflow : Int64

    @io : IO
    @next_sequence : UInt64
    @handoffs : Hash(UInt64, LowerMissingDemandHandoffFacts)
    @shape_first : Hash(UInt64, UInt64)
    @shape_counts : Hash(UInt64, Int32)
    @shape_ambiguous : Set(UInt64)
    @queued : Hash(UInt64, LowerMissingDemandQueuedFacts)
    @reserved : Int32
    @function_count_start : Int32
    @pending_start : Int32

    def initialize(
      @limit : Int32 = DEFAULT_LIMIT,
      @io : IO = STDERR,
      @function_count_start : Int32 = 0,
      @pending_start : Int32 = 0,
    )
      normalized = @limit
      normalized = DEFAULT_LIMIT if normalized <= 0
      normalized = MAX_LIMIT if normalized > MAX_LIMIT
      @limit = normalized
      @emitted = 0_i32
      @overflow = 0_i64
      @next_sequence = 0_u64
      @handoffs = {} of UInt64 => LowerMissingDemandHandoffFacts
      @shape_first = {} of UInt64 => UInt64
      @shape_counts = {} of UInt64 => Int32
      @shape_ambiguous = Set(UInt64).new
      @queued = {} of UInt64 => LowerMissingDemandQueuedFacts
      @reserved = 0_i32
    end

    # Observe only scalar handoff facts.  The map is bounded by the same event
    # limit and is cleared with the short-lived ledger at the end of this
    # lower_missing invocation.
    def observe(
      name : String,
      handoff : Adamas::Compiler::Semantic::CallResolutionHandoff?,
      arg_types : Array(TypeRef),
      has_block : Bool,
    ) : Nil
      key = LowerMissingDemandIdentity.hash_name(name)
      if @shape_first.has_key?(key)
        if @shape_first[key] != shape_fingerprint(handoff, arg_types, has_block)
          @shape_ambiguous.add(key)
          @shape_counts[key] = (@shape_counts[key]? || 1) + 1
        end
      else
        if @shape_first.size >= @limit
          @overflow += 1_i64
          return
        end
        @shape_first[key] = shape_fingerprint(handoff, arg_types, has_block)
        @shape_counts[key] = 1
      end
      if handoff && !@handoffs.has_key?(key)
        if @handoffs.size >= @limit
          @overflow += 1_i64
          return
        end
        @handoffs[key] = LowerMissingDemandHandoffFacts.from(handoff)
      end
    end

    private def shape_fingerprint(
      handoff : Adamas::Compiler::Semantic::CallResolutionHandoff?,
      arg_types : Array(TypeRef),
      has_block : Bool,
    ) : UInt64
      hash = LowerMissingDemandIdentity::FNV_OFFSET
      if handoff
        identity = handoff.body_key.def_identity
        hash = LowerMissingDemandIdentity.mix_u64(hash, identity.arena_id)
        hash = LowerMissingDemandIdentity.mix_u64(hash, identity.expr_index.to_i64.to_u64)
        if receiver = handoff.body_key.receiver_type
          hash = LowerMissingDemandIdentity.mix_u64(hash, 1_u64)
          hash = LowerMissingDemandIdentity.mix_u64(hash, receiver.id.to_u64)
        else
          hash = LowerMissingDemandIdentity.mix_u64(hash, 0_u64)
        end
        handoff.body_key.arg_types.each do |type|
          hash = LowerMissingDemandIdentity.mix_u64(hash, type.id.to_u64)
        end
        if block = handoff.body_key.block_type
          hash = LowerMissingDemandIdentity.mix_u64(hash, 1_u64)
          hash = LowerMissingDemandIdentity.mix_u64(hash, block.id.to_u64)
        else
          hash = LowerMissingDemandIdentity.mix_u64(hash, 0_u64)
        end
        if named = handoff.body_key.named_arg_types
          named.each do |name_id, type|
            hash = LowerMissingDemandIdentity.mix_u64(hash, name_id.id.to_u64)
            hash = LowerMissingDemandIdentity.mix_u64(hash, type.id.to_u64)
          end
        end
      end
      hash = LowerMissingDemandIdentity.mix_u64(hash, arg_types.size.to_u64)
      arg_types.each do |type|
        hash = LowerMissingDemandIdentity.mix_u64(hash, type.id.to_u64)
      end
      hash = LowerMissingDemandIdentity.mix_u64(hash, has_block ? 1_u64 : 0_u64)
      hash
    end

    private def shape_facts_for(key : UInt64) : LowerMissingDemandShapeFacts
      LowerMissingDemandShapeFacts.new(
        @shape_first[key]? || 0_u64,
        (@shape_counts[key]? || 1) - 1,
        @shape_ambiguous.includes?(key),
      )
    end

    private def delete_shape_facts(key : UInt64) : LowerMissingDemandShapeFacts
      facts = shape_facts_for(key)
      @shape_first.delete(key)
      @shape_counts.delete(key)
      @shape_ambiguous.delete(key)
      facts
    end

    # Records only the scalar fact that the legacy implementation has already
    # appended to its queue.  A terminal row is streamed after processing, so
    # this map is bounded and contains no source/HIR objects or strings.
    def queued(
      iteration : Int32,
      context : LowerMissingDemandContext,
      reason : LowerMissingDemandReason,
      name : String,
      function_count_before : Int32,
      pending_before : Int32,
    ) : Nil
      key = LowerMissingDemandIdentity.hash_name(name)
      return if @queued.has_key?(key)
      if @emitted + @reserved >= @limit
        @overflow += 1_i64
        return
      end
      @queued[key] = LowerMissingDemandQueuedFacts.new(
        iteration,
        context,
        reason,
        function_count_before,
        pending_before,
      )
      @reserved += 1
    end

    # Completes a previously admitted queue row.  One terminal row contains
    # both the fact that enqueue occurred and its resulting outcome; no token
    # or name-to-sequence array is retained.
    def outcome(
      name : String,
      status : LowerMissingDemandOutcome,
      function_count_after : Int32,
      pending_after : Int32,
    ) : Nil
      requested_identity = LowerMissingDemandIdentity.hash_name(name)
      queued = @queued.delete(requested_identity)
      return unless queued
      @reserved -= 1
      sequence = @next_sequence
      @next_sequence += 1_u64
      @emitted += 1
      materialized_identity = status == LowerMissingDemandOutcome::Materialized ? requested_identity : 0_u64
      handoff_facts = @handoffs.delete(requested_identity)
      shape_facts = delete_shape_facts(requested_identity)
      emit_row(
        sequence,
        LowerMissingDemandEvent::Demand,
        queued.iteration,
        queued.context,
        queued.reason,
        name,
        requested_identity,
        materialized_identity,
        status,
        handoff_facts,
        queued.function_count_before,
        function_count_after,
        queued.pending_before,
        pending_after,
        shape_facts,
      )
    end

    def summary(
      iteration : Int32,
      context : LowerMissingDemandContext,
      function_count_end : Int32? = nil,
      pending_end : Int32? = nil,
    ) : Nil
      final_function_count = function_count_end || @function_count_start
      final_pending = pending_end || @pending_start
      @io << "[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event="
      @io << event_label(LowerMissingDemandEvent::Summary)
      @io << " iteration=" << iteration
      @io << " context=" << context_label(context)
      @io << " emitted=" << @emitted
      @io << " overflow=" << @overflow
      @io << " unfinished=" << @queued.size
      @io << " limit=" << @limit
      @io << " function_count_start=" << @function_count_start
      @io << " function_count_end=" << final_function_count
      @io << " pending_start=" << @pending_start
      @io << " pending_end=" << final_pending
      @io << " complete=1"
      @io << "\n"
    end

    # A start checkpoint survives a timeout or external kill that occurs in
    # lower_missing before the final summary can be written. Checkpoints are
    # fixed in number (one start and one completion per invocation) and do not
    # consume the demand-row cap.
    def checkpoint(iteration : Int32, context : LowerMissingDemandContext, complete : Bool) : Nil
      @io << "[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1 event="
      @io << event_label(LowerMissingDemandEvent::Checkpoint)
      @io << " iteration=" << iteration
      @io << " context=" << context_label(context)
      @io << " complete=" << (complete ? 1 : 0)
      @io << "\n"
    end

    private def emit_row(
      sequence : UInt64,
      event : LowerMissingDemandEvent,
      iteration : Int32,
      context : LowerMissingDemandContext,
      reason : LowerMissingDemandReason,
      name : String,
      requested_identity : UInt64,
      materialized_identity : UInt64,
      status : LowerMissingDemandOutcome,
      handoff : LowerMissingDemandHandoffFacts?,
      function_count_before : Int32,
      function_count_after : Int32,
      pending_before : Int32,
      pending_after : Int32,
      shape_facts : LowerMissingDemandShapeFacts,
    ) : Nil
      owner_kind = LowerMissingDemandIdentity.owner_kind(name)
      owner_identity = LowerMissingDemandIdentity.owner_identity(name)
      @io << "[LOWER_MISSING_LEDGER] schema=lower_missing_demand_v1"
      @io << " event=" << event_label(event)
      @io << " seq=" << sequence
      @io << " iteration=" << iteration
      @io << " context=" << context_label(context)
      @io << " reason=" << reason_label(reason)
      @io << " owner_kind=" << owner_label(owner_kind)
      @io << " owner_id="
      write_hex(owner_identity)
      @io << " requested_id="
      write_hex(requested_identity)
      @io << " materialized_id="
      write_hex(materialized_identity)
      @io << " enqueue=1"
      @io << " function_count_before=" << function_count_before
      @io << " function_count_after=" << function_count_after
      @io << " pending_before=" << pending_before
      @io << " pending_after=" << pending_after
      @io << " hir_arg_shape_id="
      write_hex(shape_facts.fingerprint)
      @io << " shape_mismatch_count=" << shape_facts.mismatch_count
      @io << " shape_ambiguous=" << (shape_facts.ambiguous ? 1 : 0)
      @io << " outcome=" << outcome_label(status)
      if handoff
        @io << " handoff=1"
        @io << " resolution_id=" << handoff.resolution_id
        @io << " callsite_arena_id="
        write_hex(handoff.callsite_arena_id)
        @io << " callsite_expr_id=" << handoff.callsite_expr_id
        @io << " def_arena_id="
        write_hex(handoff.def_arena_id)
        @io << " def_expr_id=" << handoff.def_expr_id
        @io << " receiver_type_id=" << handoff.receiver_type_id
        @io << " arg_count=" << handoff.arg_count
        @io << " block_type_id=" << handoff.block_type_id
      else
        @io << " handoff=0"
        @io << " resolution_id=0 callsite_arena_id=0 callsite_expr_id=-1"
        @io << " def_arena_id=0 def_expr_id=-1 receiver_type_id=0 arg_count=0 block_type_id=0"
      end
      @io << "\n"
    end

    private def context_label(context : LowerMissingDemandContext) : String
      case context
      when .initial? then "initial"
      when .final?   then "final"
      else                "unknown"
      end
    end

    private def event_label(event : LowerMissingDemandEvent) : String
      case event
      when .demand?     then "demand"
      when .summary?    then "summary"
      when .checkpoint? then "checkpoint"
      else                   "unknown"
      end
    end

    # Stream hexadecimal identities without allocating an intermediate String.
    private def write_hex(value : UInt64) : Nil
      @io << "0x"
      shift = 60
      started = false
      while shift >= 0
        digit = ((value >> shift) & 0x0f_u64).to_i
        if started || digit != 0
          @io.write_byte(HEX_DIGITS.to_unsafe[digit])
          started = true
        end
        shift -= 4
      end
      @io.write_byte('0'.ord.to_u8) unless started
    end

    private def reason_label(reason : LowerMissingDemandReason) : String
      case reason
      when .call_target?     then "call_target"
      when .super_alias?     then "super_alias"
      when .super_target?    then "super_target"
      when .module_fallback? then "module_fallback"
      else                        "unknown"
      end
    end

    private def owner_label(owner : LowerMissingDemandOwnerKind) : String
      case owner
      when .top_level? then "top_level"
      when .instance?  then "instance"
      when .class?     then "class"
      else                  "unknown"
      end
    end

    private def outcome_label(outcome : LowerMissingDemandOutcome) : String
      case outcome
      when .enqueued?      then "enqueued"
      when .materialized?  then "materialized"
      when .deferred?      then "deferred"
      when .still_missing? then "still_missing"
      when .skipped?       then "skipped"
      else                      "unknown"
      end
    end
  end
end
