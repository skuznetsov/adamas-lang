#!/usr/bin/env crystal

require "../src/compiler/hir/lowering_binary_trace"

module Adamas::Tools
  alias TraceFormat = Adamas::HIR::LoweringBinaryTrace

  private record ChunkHeader,
    kind : UInt16,
    payload_bytes : UInt32,
    item_count : UInt32,
    first_sequence : UInt64

  private record TraceEvent,
    sequence : UInt32,
    delta_ns : UInt64,
    event_id : UInt16,
    depth : UInt16,
    value : UInt64,
    caller : String?,
    symbol : String?

  private record MaterializationSample,
    symbol : String,
    parent : String?,
    first_requester : String?,
    duration_ns : UInt64,
    self_ns : UInt64,
    depth : UInt16,
    start_sequence : UInt32,
    missing_sweep : UInt32?,
    missing_iteration : UInt32?

  private record ConcretePhaseSample,
    symbol : String,
    site : String,
    duration_ns : UInt64,
    self_ns : UInt64,
    start_sequence : UInt32

  private class ActiveMaterialization
    getter event : TraceEvent
    getter first_requester : String?
    getter missing_sweep : UInt32?
    getter missing_iteration : UInt32?
    property child_ns : UInt64

    def initialize(
      @event : TraceEvent,
      @first_requester : String?,
      @missing_sweep : UInt32?,
      @missing_iteration : UInt32?,
    )
      @child_ns = 0_u64
    end
  end

  private class ActiveConcreteRegistration
    getter symbol : String
    getter started : TraceEvent
    property last_marker : TraceEvent
    property child_ns : UInt64
    property self_ns : UInt64
    property invalid : Bool

    def initialize(@symbol : String, @started : TraceEvent)
      @last_marker = @started
      @child_ns = 0_u64
      @self_ns = 0_u64
      @invalid = false
    end
  end

  private class ActiveNestedRegistration
    getter symbol : String
    getter started : TraceEvent
    getter parent_symbol : String
    getter parent_phase : String
    property child_ns : UInt64

    def initialize(
      @symbol : String,
      @started : TraceEvent,
      @parent_symbol : String,
      @parent_phase : String,
    )
      @child_ns = 0_u64
    end
  end

  private record PhaseSample,
    index : UInt64,
    duration_ns : UInt64,
    initial : UInt64,
    result : UInt64,
    requests : Int32,
    materializations : Int32

  private record RequestProfileSample,
    site_line : UInt32,
    target : String,
    before_state : TraceFormat::RequestProfileState,
    after_state : TraceFormat::RequestProfileState,
    duration_us : UInt64,
    saturated : Bool

  private class TraceRun
    getter index : Int32
    getter pid : UInt32
    getter start_ticks : UInt64
    getter capacity_records : UInt32
    getter flush_interval_ns : UInt64
    getter events : Array(TraceEvent)
    property summary : Tuple(UInt64, UInt64, UInt64, UInt64, UInt64)?

    def initialize(
      @index : Int32,
      @pid : UInt32,
      @start_ticks : UInt64,
      @capacity_records : UInt32,
      @flush_interval_ns : UInt64,
    )
      @events = [] of TraceEvent
      @summary = nil
    end
  end

  private class LoweringTraceAnalyzer
    getter runs : Array(TraceRun)
    getter recovered_segments : Int32
    getter truncated_tail : Bool

    def initialize(@path : String)
      @runs = [] of TraceRun
      @recovered_segments = 0
      @truncated_tail = false
    end

    def parse : Nil
      File.open(@path, "rb") do |io|
        file_size = io.size
        offset = 0_i64
        symbols = {} of UInt64 => String
        current_run : TraceRun? = nil

        while offset < file_size
          begin
            header = read_header_at(io, offset, file_size)
            unless header
              if recovered_at = find_next_run(io, offset + 1, file_size)
                @recovered_segments += 1
                offset = recovered_at
                next
              end
              @truncated_tail = true
              break
            end

            footer_offset = offset + TraceFormat::CHUNK_HEADER_BYTES + header.payload_bytes.to_i64
            unless valid_footer_at(io, footer_offset, header, file_size)
              if recovered_at = find_next_run(io, offset + 1, file_size)
                @recovered_segments += 1
                offset = recovered_at
                next
              end
              @truncated_tail = true
              break
            end

            payload = Bytes.new(header.payload_bytes.to_i)
            io.seek(offset + TraceFormat::CHUNK_HEADER_BYTES)
            io.read_fully(payload)

            case header.kind
            when TraceFormat::CHUNK_RUN
              current_run = parse_run(payload)
              @runs << current_run
              symbols.clear
            when TraceFormat::CHUNK_SYMBOLS
              parse_symbols(payload, header.item_count, symbols)
            when TraceFormat::CHUNK_EVENTS
              if run = current_run
                parse_events(payload, header, symbols, run)
              end
            when TraceFormat::CHUNK_SUMMARY
              if run = current_run
                run.summary = parse_summary(payload)
              end
            end

            offset += TraceFormat::CHUNK_HEADER_BYTES +
                      header.payload_bytes.to_i64 +
                      TraceFormat::CHUNK_FOOTER_BYTES
          rescue IO::EOFError | IndexError
            if recovered_at = find_next_run(io, offset + 1, file_size)
              @recovered_segments += 1
              offset = recovered_at
            else
              @truncated_tail = true
              break
            end
          end
        end
      end
    end

    def print_summary(
      top : Int32,
      tail : Int32,
      virtual_target_match : String?,
      event_window : Tuple(UInt32, Int32)?,
      event_match : String?,
    ) : Nil
      puts "trace=#{@path} runs=#{@runs.size} recovered_segments=#{@recovered_segments} truncated_tail=#{@truncated_tail ? 1 : 0}"
      @runs.each do |run|
        print_run(run, top, tail, virtual_target_match, event_window, event_match)
      end
    end

    private def parse_run(payload : Bytes) : TraceRun
      TraceRun.new(
        @runs.size,
        read_u32(payload, 8),
        read_u64(payload, 0),
        read_u32(payload, 16),
        read_u64(payload, 24),
      )
    end

    private def parse_symbols(
      payload : Bytes,
      item_count : UInt32,
      symbols : Hash(UInt64, String),
    ) : Nil
      offset = 0
      item_count.times do
        symbol_id = read_u64(payload, offset)
        bytesize = read_u32(payload, offset + 8).to_i
        offset += 12
        raise IndexError.new if bytesize > payload.size - offset
        symbols[symbol_id] = String.new(payload[offset, bytesize])
        offset += bytesize
      end
      raise IndexError.new unless offset == payload.size
    end

    private def parse_events(
      payload : Bytes,
      header : ChunkHeader,
      symbols : Hash(UInt64, String),
      run : TraceRun,
    ) : Nil
      header.item_count.times do |index|
        offset = index.to_i * TraceFormat::EVENT_RECORD_BYTES
        delta_ns = read_u64(payload, offset)
        value = read_u64(payload, offset + 8)
        packed = read_u64(payload, offset + 16)
        sequence = (packed & 0xffff_ffff_u64).to_u32
        expected = (header.first_sequence + index).to_u32
        raise IndexError.new unless sequence == expected
        if previous = run.events.last?
          raise IndexError.new unless sequence == previous.sequence &+ 1_u32
        else
          raise IndexError.new unless sequence == 1_u32
        end
        event_id = ((packed >> 32) & 0xffff_u64).to_u16
        depth = ((packed >> 48) & 0xffff_u64).to_u16
        caller = nil.as(String?)
        symbol = nil.as(String?)
        if event_id == TraceFormat::Event::LowerRequestEdge.value
          caller = symbols[value & 0xffff_ffff_u64]?
          symbol = symbols[value >> 32]?
        elsif event_id == TraceFormat::Event::LowerRequestSite.value
          caller = "<site:src/compiler/hir/ast_to_hir.cr:#{value & 0xffff_ffff_u64}>"
          symbol = symbols[value >> 32]?
        elsif site_symbol_event?(event_id)
          caller = symbols[value & 0xffff_ffff_u64]?
          symbol = symbols[value >> 32]?
        elsif symbol_event?(event_id)
          symbol = symbols[value]?
        end
        run.events << TraceEvent.new(sequence, delta_ns, event_id, depth, value, caller, symbol)
      end
    end

    private def parse_summary(payload : Bytes) : Tuple(UInt64, UInt64, UInt64, UInt64, UInt64)
      {
        read_u64(payload, 0),
        read_u64(payload, 8),
        read_u64(payload, 16),
        read_u64(payload, 24),
        read_u64(payload, 32),
      }
    end

    private def print_run(
      run : TraceRun,
      top : Int32,
      tail : Int32,
      virtual_target_match : String?,
      event_window : Tuple(UInt32, Int32)?,
      event_match : String?,
    ) : Nil
      puts "run=#{run.index} pid=#{run.pid} events=#{run.events.size} capacity=#{run.capacity_records} flush_ms=#{run.flush_interval_ns // 1_000_000_u64}"
      if summary = run.summary
        total, dropped, flushes, bytes, write_ns = summary
        puts "  summary total=#{total} dropped=#{dropped} flushes=#{flushes} bytes=#{bytes} write_ms=#{format_ms(write_ns)}"
      else
        puts "  summary incomplete=1"
      end

      event_counts = Hash(String, Int32).new(0)
      symbol_counts = Hash(String, Hash(UInt16, Int32)).new
      request_edges = Hash(Tuple(String, String), Int32).new(0)
      # Keep the semantic origin before a later queue-drain site obscures it.
      first_requester_by_target = {} of String => String
      virtual_target_edges = Hash(Tuple(String, String), Int32).new(0)
      virtual_target_replay_edges = Hash(Tuple(String, String), Int32).new(0)
      strict_virtual_target_materialization_edges = Hash(Tuple(String, String), Int32).new(0)
      pending_virtual_target_replay = nil.as(Tuple(String, String, UInt32)?)
      active_materializations = [] of ActiveMaterialization
      materializations = [] of MaterializationSample
      unmatched_materializations = 0
      active_concrete_registrations = [] of ActiveConcreteRegistration
      concrete_registration_totals = Hash(String, Tuple(Int32, UInt64, UInt64)).new
      concrete_symbol_totals = Hash(String, Tuple(Int32, UInt64, UInt64)).new
      concrete_phase_totals = Hash(Tuple(String, String), Tuple(Int32, UInt64, UInt64, UInt64)).new
      concrete_phase_samples = [] of ConcretePhaseSample
      unmatched_concrete_registrations = 0
      invalid_concrete_intervals = 0
      active_nested_registrations = [] of ActiveNestedRegistration
      nested_registration_totals = Hash(Tuple(String, String, String), Tuple(Int32, UInt64, UInt64, UInt64)).new
      unmatched_nested_registrations = 0
      processes = [] of PhaseSample
      passes = [] of PhaseSample
      phase_events = [] of TraceEvent
      active_process : TraceEvent? = nil
      process_requests = 0
      process_materializations = 0
      active_pass : TraceEvent? = nil
      pass_requests = 0
      pass_materializations = 0
      next_missing_sweep = 0_u32
      active_missing_sweep = nil.as(UInt32?)
      active_missing_iteration = nil.as(UInt32?)
      completed_missing_iterations = Set(Tuple(UInt32, UInt32)).new
      request_profile_enabled = run.events.any? do |event|
        event.event_id == TraceFormat::Event::LowerRequestProfile.value
      end
      active_profile_requests = [] of TraceEvent
      request_profiles = [] of RequestProfileSample
      unmatched_request_profiles = 0
      run.events.each do |event|
        if pending = pending_virtual_target_replay
          source, target, prior_sequence = pending
          if event.sequence == prior_sequence &+ 1_u32
            if lower_request_event?(event.event_id) && event.symbol == target
              pending_virtual_target_replay = {source, target, event.sequence}
            elsif event.event_id == TraceFormat::Event::MaterializeStart.value && event.symbol == target
              strict_virtual_target_materialization_edges[{source, target}] += 1
              pending_virtual_target_replay = nil
            else
              pending_virtual_target_replay = nil
            end
          else
            pending_virtual_target_replay = nil
          end
        end

        event_counts[event_name(event.event_id)] += 1
        if (symbol = event.symbol) && !site_symbol_event?(event.event_id)
          # Concrete registration has its own family and phase reports below;
          # including every checkpoint here would hide lowering hot symbols.
          per_event = symbol_counts[symbol]? || begin
            created = Hash(UInt16, Int32).new(0)
            symbol_counts[symbol] = created
            created
          end
          per_event[event.event_id] += 1
        end

        if active_process
          process_requests += 1 if lower_request_event?(event.event_id)
          process_materializations += 1 if event.event_id == TraceFormat::Event::MaterializeStart.value
        end
        if active_pass
          pass_requests += 1 if lower_request_event?(event.event_id)
          pass_materializations += 1 if event.event_id == TraceFormat::Event::MaterializeStart.value
        end

        if request_profile_enabled && lower_request_event?(event.event_id)
          active_profile_requests << event
        elsif event.event_id == TraceFormat::Event::LowerRequestProfile.value
          if request = active_profile_requests.pop?
            transition = (event.value >> 56).to_u8
            before_state = TraceFormat::RequestProfileState.from_value?(transition & 0x0f_u8)
            after_state = TraceFormat::RequestProfileState.from_value?(transition >> 4)
            duration_us = (event.value >> 32) & 0x00ff_ffff_u64
            if target = request.symbol
              if before_state && after_state
                request_profiles << RequestProfileSample.new(
                  (event.value & 0xffff_ffff_u64).to_u32,
                  target,
                  before_state,
                  after_state,
                  duration_us,
                  duration_us == TraceFormat::MAX_PROFILE_DURATION_US,
                )
              else
                unmatched_request_profiles += 1
              end
            else
              unmatched_request_profiles += 1
            end
          else
            unmatched_request_profiles += 1
          end
        end

        case event.event_id
        when TraceFormat::Event::ProcessStart.value
          active_process = event
          process_requests = 0
          process_materializations = 0
        when TraceFormat::Event::ProcessDone.value
          if started = active_process
            processes << PhaseSample.new(
              processes.size.to_u64,
              event.delta_ns - started.delta_ns,
              started.value,
              event.value,
              process_requests,
              process_materializations,
            )
          end
          active_process = nil
        when TraceFormat::Event::PassStart.value
          active_pass = event
          pass_requests = 0
          pass_materializations = 0
        when TraceFormat::Event::PassDone.value
          if started = active_pass
            pass_index = event.value & 0xffff_ffff_u64
            lowered = event.value >> 32
            passes << PhaseSample.new(
              pass_index,
              event.delta_ns - started.delta_ns,
              started.value,
              lowered,
              pass_requests,
              pass_materializations,
            )
          end
          active_pass = nil
        when TraceFormat::Event::LowerRequest.value,
             TraceFormat::Event::LowerRequestEdge.value,
             TraceFormat::Event::LowerRequestSite.value
          if callee = event.symbol
            caller = event.caller ||
                     active_materializations.last?.try(&.event.symbol) ||
                     "<root/phase>"
            request_edges[{caller, callee}] += 1
            first_requester_by_target[callee] ||= caller
          end
        when TraceFormat::Event::VirtualTargetRecord.value
          if source = event.caller
            if target = event.symbol
              virtual_target_edges[{source, target}] += 1
            end
          end
        when TraceFormat::Event::VirtualTargetReplay.value
          if source = event.caller
            if target = event.symbol
              virtual_target_replay_edges[{source, target}] += 1
              first_requester_by_target[target] ||= "<virtual-replay:#{source}>"
              pending_virtual_target_replay = {source, target, event.sequence}
            end
          end
        when TraceFormat::Event::MaterializeStart.value
          active_materializations << ActiveMaterialization.new(
            event,
            event.symbol.try { |symbol| first_requester_by_target[symbol]? },
            active_missing_sweep,
            active_missing_iteration,
          )
        when TraceFormat::Event::MaterializeDone.value
          if active = active_materializations.pop?
            started = active.event
            if symbol = event.symbol
              if symbol == started.symbol
                duration_ns = event.delta_ns - started.delta_ns
                self_ns = duration_ns >= active.child_ns ? duration_ns - active.child_ns : 0_u64
                materializations << MaterializationSample.new(
                  symbol,
                  active_materializations.last?.try(&.event.symbol),
                  active.first_requester,
                  duration_ns,
                  self_ns,
                  event.depth,
                  started.sequence,
                  active.missing_sweep,
                  active.missing_iteration,
                )
                if parent = active_materializations.last?
                  parent.child_ns &+= duration_ns
                end
              else
                unmatched_materializations += 1
              end
            end
          else
            unmatched_materializations += 1
          end
        when TraceFormat::Event::ConcreteRegisterStart.value
          if symbol = event.symbol
            if event.caller
              active_concrete_registrations << ActiveConcreteRegistration.new(symbol, event)
            else
              unmatched_concrete_registrations += 1
            end
          else
            unmatched_concrete_registrations += 1
          end
        when TraceFormat::Event::ConcreteRegisterPoint.value
          if active = active_concrete_registrations.last?
            if event.symbol == active.symbol && event.caller
              if !active.invalid && !record_concrete_phase(active, event, concrete_phase_totals, concrete_phase_samples)
                invalid_concrete_intervals += 1
              end
            else
              active.invalid = true
              unmatched_concrete_registrations += 1
            end
          else
            unmatched_concrete_registrations += 1
          end
        when TraceFormat::Event::ConcreteRegisterDone.value
          if active = active_concrete_registrations.last?
            if event.symbol == active.symbol && event.caller
              if !active.invalid && !record_concrete_phase(active, event, concrete_phase_totals, concrete_phase_samples)
                invalid_concrete_intervals += 1
              end
              active_concrete_registrations.pop
              if !active.invalid && (duration_ns = elapsed_ns(active.started, event))
                accumulate_concrete_registration(
                  concrete_registration_totals,
                  generic_family(active.symbol),
                  duration_ns,
                  active.self_ns,
                )
                accumulate_concrete_registration(
                  concrete_symbol_totals,
                  active.symbol,
                  duration_ns,
                  active.self_ns,
                )
                if parent = active_concrete_registrations.last?
                  parent.child_ns &+= duration_ns
                end
              elsif parent = active_concrete_registrations.last?
                # An invalid child interval makes the parent's self-time
                # unknowable as well; never turn corrupt timing into a hot path.
                parent.invalid = true
              end
            else
              active.invalid = true
              unmatched_concrete_registrations += 1
            end
          else
            unmatched_concrete_registrations += 1
          end
        when TraceFormat::Event::NestedRegisterStart.value
          if symbol = event.symbol
            if event.caller
              parent = active_concrete_registrations.last?
              active_nested_registrations << ActiveNestedRegistration.new(
                symbol,
                event,
                parent.try(&.symbol) || "<root>",
                parent.try(&.last_marker.caller) || "<outside-concrete-phase>",
              )
            else
              unmatched_nested_registrations += 1
            end
          else
            unmatched_nested_registrations += 1
          end
        when TraceFormat::Event::NestedRegisterDone.value
          if active = active_nested_registrations.pop?
            if event.symbol == active.symbol && event.caller
              if duration_ns = elapsed_ns(active.started, event)
                self_ns = duration_ns >= active.child_ns ? duration_ns - active.child_ns : 0_u64
                key = {
                  generic_family(active.parent_symbol),
                  active.parent_phase,
                  generic_family(active.symbol),
                }
                count, total_ns, accumulated_self_ns, max_ns = nested_registration_totals[key]? || {0, 0_u64, 0_u64, 0_u64}
                nested_registration_totals[key] = {
                  count + 1,
                  total_ns &+ duration_ns,
                  accumulated_self_ns &+ self_ns,
                  duration_ns > max_ns ? duration_ns : max_ns,
                }
                if parent = active_nested_registrations.last?
                  parent.child_ns &+= duration_ns
                end
              else
                unmatched_nested_registrations += 1
              end
            else
              unmatched_nested_registrations += 1
            end
          else
            unmatched_nested_registrations += 1
          end
        when TraceFormat::Event::MissingStart.value
          active_missing_sweep = next_missing_sweep
          next_missing_sweep &+= 1_u32
          active_missing_iteration = nil
          phase_events << event
        when TraceFormat::Event::MissingIterStart.value
          active_missing_iteration = (event.value & 0xffff_ffff_u64).to_u32
          phase_events << event
        when TraceFormat::Event::MissingIterDone.value
          if sweep = active_missing_sweep
            completed_missing_iterations << {
              sweep,
              (event.value & 0xffff_ffff_u64).to_u32,
            }
          end
          active_missing_iteration = nil
          phase_events << event
        when TraceFormat::Event::MissingDone.value
          active_missing_sweep = nil
          active_missing_iteration = nil
          phase_events << event
        when TraceFormat::Event::MissingScanDone.value
          phase_events << event
        end
      end
      unmatched_materializations += active_materializations.size
      unmatched_concrete_registrations += active_concrete_registrations.size
      unmatched_nested_registrations += active_nested_registrations.size
      unmatched_request_profiles += active_profile_requests.size if request_profile_enabled
      puts "  event_counts:"
      event_counts.to_a.sort_by(&.[0]).each do |name, count|
        puts "    #{count.to_s.rjust(8)}  #{name}"
      end
      hot = symbol_counts.to_a.sort_by do |name, counts|
        {-counts.values.sum, name}
      end.first(top)
      puts "  hot_symbols:"
      hot.each do |name, counts|
        total = counts.values.sum
        enqueue = counts[TraceFormat::Event::QueueEnqueue.value]
        visit = counts[TraceFormat::Event::QueueVisit.value]
        request = counts[TraceFormat::Event::LowerRequest.value] +
                  counts[TraceFormat::Event::LowerRequestEdge.value] +
                  counts[TraceFormat::Event::LowerRequestSite.value]
        start = counts[TraceFormat::Event::MaterializeStart.value]
        done = counts[TraceFormat::Event::MaterializeDone.value]
        puts "    #{total.to_s.rjust(8)} q=#{enqueue} v=#{visit} req=#{request} mat=#{start}/#{done}  #{name}"
      end

      materialization_totals = Hash(String, Tuple(Int32, UInt64, UInt64)).new
      materializations.each do |sample|
        count, total_ns, self_ns = materialization_totals[sample.symbol]? || {0, 0_u64, 0_u64}
        materialization_totals[sample.symbol] = {
          count + 1,
          total_ns &+ sample.duration_ns,
          self_ns &+ sample.self_ns,
        }
      end
      repeated = materialization_totals.compact_map do |name, totals|
        totals[0] > 1 ? {name, totals} : nil
      end.sort_by { |name, totals| {-totals[0], name} }.first(top)
      puts "  repeated_materializations:"
      repeated.each do |name, totals|
        count, total_ns, self_ns = totals
        puts "    #{count.to_s.rjust(8)} total_ms=#{format_ms(total_ns)} self_ms=#{format_ms(self_ns)}  #{name}"
      end

      materializations_by_iteration = Hash(Tuple(UInt32, UInt32), Array(MaterializationSample)).new do |by_iteration, key|
        by_iteration[key] = [] of MaterializationSample
      end
      first_materialization_by_symbol = {} of String => MaterializationSample
      materializations.each do |sample|
        previous = first_materialization_by_symbol[sample.symbol]?
        if previous.nil? || sample.start_sequence < previous.start_sequence
          first_materialization_by_symbol[sample.symbol] = sample
        end
        if (sweep = sample.missing_sweep) && (iteration = sample.missing_iteration)
          materializations_by_iteration[{sweep, iteration}] << sample
        end
      end
      puts "  missing_iteration_materializations:"
      materializations_by_iteration.keys.sort.each do |key|
        sweep, iteration = key
        samples = materializations_by_iteration[key]
        total_ns = samples.sum(0_u64, &.duration_ns)
        self_ns = samples.sum(0_u64, &.self_ns)
        unique = samples.map(&.symbol).uniq.size
        complete = completed_missing_iterations.includes?(key) ? 1 : 0
        puts "    sweep=#{sweep} iteration=#{iteration} complete=#{complete} count=#{samples.size} unique=#{unique} inclusive_ms=#{format_ms(total_ns)} self_ms=#{format_ms(self_ns)}"

        family_counts = Hash(String, Int32).new(0)
        family_total_ns = Hash(String, UInt64).new(0_u64)
        family_self_ns = Hash(String, UInt64).new(0_u64)
        family_symbols = Hash(String, Set(String)).new do |symbols, family|
          symbols[family] = Set(String).new
        end
        method_counts = Hash(String, Int32).new(0)
        method_total_ns = Hash(String, UInt64).new(0_u64)
        method_self_ns = Hash(String, UInt64).new(0_u64)
        method_symbols = Hash(String, Set(String)).new do |symbols, method|
          symbols[method] = Set(String).new
        end
        samples.each do |sample|
          family = generic_family(sample.symbol)
          family_counts[family] += 1
          family_total_ns[family] &+= sample.duration_ns
          family_self_ns[family] &+= sample.self_ns
          family_symbols[family] << sample.symbol

          method = method_family_prefix(sample.symbol)
          method_counts[method] += 1
          method_total_ns[method] &+= sample.duration_ns
          method_self_ns[method] &+= sample.self_ns
          method_symbols[method] << sample.symbol
        end
        family_self_ns.to_a.sort_by do |family, accumulated_self_ns|
          {-accumulated_self_ns.to_i128, -family_counts[family], family}
        end.first(top).each do |family, accumulated_self_ns|
          puts "      self_ms=#{format_ms(accumulated_self_ns).rjust(12)} inclusive_ms=#{format_ms(family_total_ns[family]).rjust(12)} count=#{family_counts[family].to_s.rjust(8)} unique=#{family_symbols[family].size.to_s.rjust(6)} family_prefix=#{family}"
        end
        method_self_ns.to_a.sort_by do |method, accumulated_self_ns|
          {-accumulated_self_ns.to_i128, -method_counts[method], method}
        end.first(top).each do |method, accumulated_self_ns|
          puts "      self_ms=#{format_ms(accumulated_self_ns).rjust(12)} inclusive_ms=#{format_ms(method_total_ns[method]).rjust(12)} count=#{method_counts[method].to_s.rjust(8)} unique=#{method_symbols[method].size.to_s.rjust(6)} method_prefix=#{method}"
        end

        new_samples = samples.select do |sample|
          first_materialization_by_symbol[sample.symbol]?.try(&.start_sequence) == sample.start_sequence
        end
        first_requester_counts = Hash(String, Int32).new(0)
        first_requester_family_counts = Hash(String, Hash(String, Int32)).new do |by_requester, requester|
          by_requester[requester] = Hash(String, Int32).new(0)
        end
        new_samples.each do |sample|
          requester = sample.first_requester || "<unknown>"
          first_requester_counts[requester] += 1
          first_requester_family_counts[requester][generic_family(sample.symbol)] += 1
        end
        puts "      first_materialization_origins new=#{new_samples.size} attributed=#{new_samples.count { |sample| !sample.first_requester.nil? }}"
        first_requester_counts.to_a.sort_by do |requester, count|
          {-count, requester}
        end.first(top).each do |requester, count|
          families = first_requester_family_counts[requester].to_a
            .sort_by { |family, family_count| {-family_count, family} }
            .first(3)
            .map { |family, family_count| "#{family}=#{family_count}" }
            .join(",")
          puts "        new=#{count.to_s.rjust(8)} families=#{families} first_requested_by=#{requester}"
        end
      end

      concrete_families = concrete_registration_totals.to_a.sort_by do |family, totals|
        {-totals[2].to_i128, -totals[1].to_i128, family}
      end.first(top)
      concrete_unique_symbols = Hash(String, Int32).new(0)
      concrete_symbol_totals.each_key do |symbol|
        concrete_unique_symbols[generic_family(symbol)] += 1
      end
      puts "  concrete_registration_families: unmatched=#{unmatched_concrete_registrations} invalid_intervals=#{invalid_concrete_intervals}"
      concrete_families.each do |family, totals|
        count, total_ns, self_ns = totals
        unique = concrete_unique_symbols[family]
        puts "    self_ms=#{format_ms(self_ns).rjust(12)} total_ms=#{format_ms(total_ns).rjust(12)} count=#{count.to_s.rjust(8)} unique=#{unique.to_s.rjust(6)}  #{family}"
      end

      repeated_concrete_symbols = concrete_symbol_totals.compact_map do |symbol, totals|
        totals[0] > 1 ? {symbol, totals} : nil
      end.sort_by do |symbol, totals|
        {-totals[2].to_i128, -totals[0], symbol}
      end.first(top)
      puts "  repeated_concrete_registrations:"
      repeated_concrete_symbols.each do |symbol, totals|
        count, total_ns, self_ns = totals
        puts "    self_ms=#{format_ms(self_ns).rjust(12)} total_ms=#{format_ms(total_ns).rjust(12)} count=#{count.to_s.rjust(8)}  #{symbol}"
      end

      concrete_phases = concrete_phase_totals.to_a.sort_by do |key, totals|
        {-totals[2].to_i128, -totals[1].to_i128, key[0], key[1]}
      end.first(top)
      puts "  concrete_registration_phases:"
      concrete_phases.each do |key, totals|
        family, site = key
        count, total_ns, self_ns, max_self_ns = totals
        puts "    self_ms=#{format_ms(self_ns).rjust(12)} total_ms=#{format_ms(total_ns).rjust(12)} max_self_ms=#{format_ms(max_self_ns).rjust(12)} count=#{count.to_s.rjust(8)} family=#{family} site=#{site}"
      end
      puts "  longest_concrete_registration_phases:"
      concrete_phase_samples.sort_by { |sample| {-sample.self_ns.to_i128, sample.symbol, sample.site} }.first(top).each do |sample|
        puts "    self_ms=#{format_ms(sample.self_ns).rjust(12)} total_ms=#{format_ms(sample.duration_ns).rjust(12)} seq=#{sample.start_sequence} symbol=#{sample.symbol} site=#{sample.site}"
      end

      nested_registrations = nested_registration_totals.to_a.sort_by do |key, totals|
        {-totals[2].to_i128, -totals[1].to_i128, key[0], key[1], key[2]}
      end.first(top)
      puts "  nested_registration_edges: unmatched=#{unmatched_nested_registrations}"
      nested_registrations.each do |key, totals|
        parent, phase, child = key
        count, total_ns, self_ns, max_ns = totals
        puts "    self_ms=#{format_ms(self_ns).rjust(12)} total_ms=#{format_ms(total_ns).rjust(12)} max_ms=#{format_ms(max_ns).rjust(12)} count=#{count.to_s.rjust(8)} parent=#{parent} phase=#{phase} child=#{child}"
      end

      edges = request_edges.to_a.sort_by do |(caller, callee), count|
        {-count, caller, callee}
      end.first(top)
      puts "  hot_request_edges:"
      edges.each do |(caller, callee), count|
        puts "    #{count.to_s.rjust(8)}  #{caller} -> #{callee}"
      end

      caller_targets = Hash(String, Set(String)).new do |targets, caller|
        targets[caller] = Set(String).new
      end
      caller_request_counts = Hash(String, Int32).new(0)
      request_edges.each do |(caller, callee), count|
        caller_targets[caller] << callee
        caller_request_counts[caller] += count
      end
      puts "  request_fanout_callers:"
      caller_targets.to_a.sort_by do |caller, targets|
        {-targets.size, -caller_request_counts[caller], caller}
      end.first(top).each do |caller, targets|
        family_counts = Hash(String, Int32).new(0)
        method_counts = Hash(String, Int32).new(0)
        targets.each do |target|
          family_counts[generic_family(target)] += 1
          method_counts[method_family_prefix(target)] += 1
        end
        families = family_counts.to_a.sort_by { |family, count| {-count, family} }
          .first(3)
          .map { |family, count| "#{family}=#{count}" }
          .join(",")
        methods = method_counts.to_a.sort_by { |method, count| {-count, method} }
          .first(3)
          .map { |method, count| "#{method}=#{count}" }
          .join(",")
        puts "    unique=#{targets.size.to_s.rjust(8)} requests=#{caller_request_counts[caller].to_s.rjust(8)} families=#{families} methods=#{methods}  #{caller}"
      end

      virtual_target_records = virtual_target_edges.to_a
      if pattern = virtual_target_match
        virtual_target_records = virtual_target_records.select do |edge, _count|
          source, target = edge
          source.includes?(pattern) || target.includes?(pattern)
        end
      end
      unless virtual_target_records.empty? && virtual_target_match.nil?
        label = virtual_target_match ? " match=#{virtual_target_match}" : ""
        puts "  virtual_target_records#{label}:"
        virtual_target_records.sort_by do |(source, target), count|
          {-count, source, target}
        end.first(top).each do |(source, target), count|
          puts "    #{count.to_s.rjust(8)}  #{source} -> #{target}"
        end
      end

      virtual_target_replays = virtual_target_replay_edges.to_a
      if pattern = virtual_target_match
        virtual_target_replays = virtual_target_replays.select do |edge, _count|
          source, target = edge
          source.includes?(pattern) || target.includes?(pattern)
        end
      end
      unless virtual_target_replays.empty? && virtual_target_match.nil?
        label = virtual_target_match ? " match=#{virtual_target_match}" : ""
        puts "  virtual_target_replays#{label}:"
        virtual_target_replays.sort_by do |(source, target), count|
          {-count, source, target}
        end.first(top).each do |(source, target), count|
          puts "    #{count.to_s.rjust(8)}  #{source} -> #{target}"
        end

        replay_targets = Hash(String, Set(String)).new do |targets, source|
          targets[source] = Set(String).new
        end
        replay_counts = Hash(String, Int32).new(0)
        virtual_target_replays.each do |(source, target), count|
          replay_targets[source] << target
          replay_counts[source] += count
        end
        puts "  virtual_target_replay_fanout#{label}:"
        replay_targets.to_a.sort_by do |source, targets|
          {-targets.size, -replay_counts[source], source}
        end.first(top).each do |source, targets|
          families = Hash(String, Int32).new(0)
          targets.each { |target| families[generic_family(target)] += 1 }
          top_families = families.to_a
            .sort_by { |family, count| {-count, family} }
            .first(3)
            .map { |family, count| "#{family}=#{count}" }
            .join(",")
          puts "    unique=#{targets.size.to_s.rjust(8)} requests=#{replay_counts[source].to_s.rjust(8)} families=#{top_families}  #{source}"
        end

        materialized_targets = Hash(String, Hash(String, Int32)).new do |targets, source|
          targets[source] = Hash(String, Int32).new(0)
        end
        materialization_counts = Hash(String, Int32).new(0)
        strict_virtual_target_materialization_edges.each do |(source, target), count|
          if pattern = virtual_target_match
            next unless source.includes?(pattern) || target.includes?(pattern)
          end
          materialized_targets[source][target] += count
          materialization_counts[source] += count
        end
        puts "  virtual_target_replay_materializations_strict#{label}:"
        materialized_targets.to_a.sort_by do |source, targets|
          {-targets.size, -materialization_counts[source], source}
        end.first(top).each do |source, targets|
          families = Hash(String, Int32).new(0)
          targets.each_key { |target| families[generic_family(target)] += 1 }
          top_families = families.to_a
            .sort_by { |family, count| {-count, family} }
            .first(3)
            .map { |family, count| "#{family}=#{count}" }
            .join(",")
          puts "    unique=#{targets.size.to_s.rjust(8)} starts=#{materialization_counts[source].to_s.rjust(8)} families=#{top_families}  #{source}"
          targets.to_a
            .sort_by { |target, count| {-count, target} }
            .first(3)
            .each do |target, count|
              puts "      #{count.to_s.rjust(8)}  #{target}"
            end
        end
      end

      profile_site_totals = Hash(Tuple(UInt32, TraceFormat::RequestProfileState, TraceFormat::RequestProfileState), Tuple(Int32, UInt64, UInt64, Int32)).new
      profile_totals = Hash(Tuple(UInt32, String, TraceFormat::RequestProfileState, TraceFormat::RequestProfileState), Tuple(Int32, UInt64, UInt64, Int32)).new
      request_profiles.each do |sample|
        site_key = {sample.site_line, sample.before_state, sample.after_state}
        site_count, site_total_us, site_max_us, site_saturated = profile_site_totals[site_key]? || {0, 0_u64, 0_u64, 0}
        profile_site_totals[site_key] = {
          site_count + 1,
          site_total_us &+ sample.duration_us,
          sample.duration_us > site_max_us ? sample.duration_us : site_max_us,
          site_saturated + (sample.saturated ? 1 : 0),
        }

        key = {sample.site_line, sample.target, sample.before_state, sample.after_state}
        count, total_us, max_us, saturated = profile_totals[key]? || {0, 0_u64, 0_u64, 0}
        profile_totals[key] = {
          count + 1,
          total_us &+ sample.duration_us,
          sample.duration_us > max_us ? sample.duration_us : max_us,
          saturated + (sample.saturated ? 1 : 0),
        }
      end
      profile_sites = profile_site_totals.to_a.sort_by do |key, totals|
        {-totals[1].to_i128, -totals[0], key[0]}
      end.first(top)
      puts "  request_profile_sites:"
      profile_sites.each do |key, totals|
        site_line, before_state, after_state = key
        count, total_us, max_us, saturated = totals
        mean_us = count > 0 ? total_us // count.to_u64 : 0_u64
        bound_suffix = saturated > 0 ? "_min" : ""
        puts "    total_ms#{bound_suffix}=#{format_ms(total_us * 1_000_u64).rjust(12)} count=#{count.to_s.rjust(8)} mean_us#{bound_suffix}=#{mean_us.to_s.rjust(8)} max_us#{bound_suffix}=#{max_us.to_s.rjust(8)} saturated=#{saturated.to_s.rjust(4)} state=#{before_state}->#{after_state} site=src/compiler/hir/ast_to_hir.cr:#{site_line}"
      end

      profiles = profile_totals.to_a.sort_by do |key, totals|
        {-totals[1].to_i128, -totals[0], key[0], key[1]}
      end.first(top)
      puts "  request_profiles: unmatched=#{unmatched_request_profiles}"
      profiles.each do |key, totals|
        site_line, target, before_state, after_state = key
        count, total_us, max_us, saturated = totals
        mean_us = count > 0 ? total_us // count.to_u64 : 0_u64
        bound_suffix = saturated > 0 ? "_min" : ""
        puts "    total_ms#{bound_suffix}=#{format_ms(total_us * 1_000_u64).rjust(12)} count=#{count.to_s.rjust(8)} mean_us#{bound_suffix}=#{mean_us.to_s.rjust(8)} max_us#{bound_suffix}=#{max_us.to_s.rjust(8)} saturated=#{saturated.to_s.rjust(4)} state=#{before_state}->#{after_state} site=src/compiler/hir/ast_to_hir.cr:#{site_line} target=#{target}"
      end

      longest = materializations.sort_by do |sample|
        {-sample.duration_ns.to_i128, sample.symbol, sample.start_sequence}
      end.first(top)
      puts "  longest_materializations: unmatched=#{unmatched_materializations}"
      longest.each do |sample|
        parent = sample.parent || "<root/phase>"
        puts "    total_ms=#{format_ms(sample.duration_ns).rjust(12)} self_ms=#{format_ms(sample.self_ns).rjust(12)} depth=#{sample.depth} seq=#{sample.start_sequence} parent=#{parent}  #{sample.symbol}"
        request_edges.compact_map do |edge, count|
          edge[1] == sample.symbol ? {edge[0], count} : nil
        end.sort_by { |caller, count| {-count, caller} }.first(5).each do |caller, count|
          puts "      requested_by=#{caller} count=#{count}"
        end
      end
      unless active_materializations.empty?
        trace_end_ns = run.events.last?.try(&.delta_ns) || 0_u64
        puts "  unfinished_materializations:"
        active_materializations.reverse_each do |active|
          elapsed_ns = trace_end_ns >= active.event.delta_ns ? trace_end_ns - active.event.delta_ns : 0_u64
          sweep = active.missing_sweep.try(&.to_s) || "none"
          iteration = active.missing_iteration.try(&.to_s) || "none"
          symbol = active.event.symbol || numeric_value(active.event)
          puts "    elapsed_ms=#{format_ms(elapsed_ns)} depth=#{active.event.depth} seq=#{active.event.sequence} sweep=#{sweep} iteration=#{iteration}  #{symbol}"
        end
      end

      puts "  processes:"
      processes.each do |sample|
        puts "    index=#{sample.index} duration_ms=#{format_ms(sample.duration_ns)} pending=#{sample.initial} lowered=#{sample.result} requests=#{sample.requests} materializations=#{sample.materializations}"
      end

      puts "  passes:"
      passes.each do |sample|
        puts "    index=#{sample.index} duration_ms=#{format_ms(sample.duration_ns)} lowered=#{sample.result} requests=#{sample.requests} materializations=#{sample.materializations}"
      end

      puts "  missing_phases:"
      phase_events.each do |event|
        puts "    seq=#{event.sequence} delta_ms=#{format_ms(event.delta_ns)} event=#{event_name(event.event_id)} value=#{numeric_value(event)}"
      end

      if window = event_window
        sequence, radius = window
        lower_sequence = sequence.to_u64 > radius.to_u64 ? sequence.to_u64 - radius.to_u64 : 1_u64
        upper_sequence = sequence.to_u64 + radius.to_u64
        puts "  event_window sequence=#{sequence} radius=#{radius}:"
        found = false
        run.events.each do |event|
          next unless lower_sequence <= event.sequence.to_u64 <= upper_sequence

          found = true
          print_event(event)
        end
        puts "    <sequence not present in this run>" unless found
      end

      if match = event_match
        matching_events = [] of TraceEvent
        matching_count = 0
        run.events.each do |event|
          next unless event.symbol.try(&.includes?(match)) || event.caller.try(&.includes?(match))

          matching_count += 1
          matching_events << event if matching_events.size < 100
        end
        puts "  matching_events text=#{match.inspect} count=#{matching_count}:"
        matching_events.each { |event| print_event(event) }
        if matching_count > matching_events.size
          puts "    <#{matching_count - matching_events.size} additional matches omitted>"
        end
      end

      return if tail <= 0
      puts "  tail:"
      run.events.last(tail).each do |event|
        print_event(event)
      end
    end

    private def print_event(event : TraceEvent) : Nil
      target = event.symbol || numeric_value(event)
      edge = event.caller ? " caller=#{event.caller}" : ""
      puts "    seq=#{event.sequence} delta_ms=#{format_ms(event.delta_ns)} depth=#{event.depth} event=#{event_name(event.event_id)} value=#{target}#{edge}"
    end

    private def numeric_value(event : TraceEvent) : String
      case event.event_id
      when TraceFormat::Event::LowerRequestProfile.value
        site_line = (event.value & 0xffff_ffff_u64).to_u32
        duration_us = (event.value >> 32) & 0x00ff_ffff_u64
        transition = (event.value >> 56).to_u8
        before_state = TraceFormat::RequestProfileState.from_value?(transition & 0x0f_u8)
        after_state = TraceFormat::RequestProfileState.from_value?(transition >> 4)
        saturated = duration_us == TraceFormat::MAX_PROFILE_DURATION_US ? ",saturated=1" : ""
        "site=#{site_line},duration_us=#{duration_us}#{saturated},state=#{before_state || "unknown"}->#{after_state || "unknown"}"
      when TraceFormat::Event::PassDone.value
        pass = (event.value & 0xffff_ffff_u64).to_u32
        lowered = (event.value >> 32).to_u32
        "pass=#{pass},lowered=#{lowered}"
      when TraceFormat::Event::MissingIterStart.value
        iteration = (event.value & 0xffff_ffff_u64).to_u32
        functions = (event.value >> 32).to_u32
        "iteration=#{iteration},functions=#{functions}"
      when TraceFormat::Event::MissingScanDone.value
        iteration = (event.value & 0xffff_ffff_u64).to_u32
        missing = (event.value >> 32).to_u32
        "iteration=#{iteration},missing=#{missing}"
      when TraceFormat::Event::MissingIterDone.value,
           TraceFormat::Event::MissingDone.value
        iteration = (event.value & 0xffff_ffff_u64).to_u32
        functions = (event.value >> 32).to_u32
        "iteration=#{iteration},functions=#{functions}"
      else
        event.value.to_s
      end
    end

    private def event_name(event_id : UInt16) : String
      if event = TraceFormat::Event.from_value?(event_id)
        event.to_s
      else
        "Unknown(#{event_id})"
      end
    end

    private def record_concrete_phase(
      active : ActiveConcreteRegistration,
      marker : TraceEvent,
      totals : Hash(Tuple(String, String), Tuple(Int32, UInt64, UInt64, UInt64)),
      samples : Array(ConcretePhaseSample),
    ) : Bool
      unless duration_ns = elapsed_ns(active.last_marker, marker)
        active.invalid = true
        active.last_marker = marker
        active.child_ns = 0_u64
        return false
      end
      self_ns = duration_ns >= active.child_ns ? duration_ns - active.child_ns : 0_u64
      family = generic_family(active.symbol)
      site = active.last_marker.caller || "<unknown-site>"
      key = {family, site}
      count, total_ns, accumulated_self_ns, max_self_ns = totals[key]? || {0, 0_u64, 0_u64, 0_u64}
      totals[key] = {
        count + 1,
        total_ns &+ duration_ns,
        accumulated_self_ns &+ self_ns,
        self_ns > max_self_ns ? self_ns : max_self_ns,
      }
      samples << ConcretePhaseSample.new(
        active.symbol,
        site,
        duration_ns,
        self_ns,
        active.last_marker.sequence,
      )
      active.self_ns &+= self_ns
      active.last_marker = marker
      active.child_ns = 0_u64
      true
    end

    private def accumulate_concrete_registration(
      totals : Hash(String, Tuple(Int32, UInt64, UInt64)),
      key : String,
      duration_ns : UInt64,
      self_ns : UInt64,
    ) : Nil
      count, accumulated_duration_ns, accumulated_self_ns = totals[key]? || {0, 0_u64, 0_u64}
      totals[key] = {
        count + 1,
        accumulated_duration_ns &+ duration_ns,
        accumulated_self_ns &+ self_ns,
      }
    end

    private def elapsed_ns(started : TraceEvent, finished : TraceEvent) : UInt64?
      return nil if finished.delta_ns < started.delta_ns
      finished.delta_ns - started.delta_ns
    end

    private def generic_family(symbol : String) : String
      if generic_start = symbol.index('(')
        symbol.byte_slice(0, generic_start)
      else
        symbol
      end
    end

    # Best-effort diagnostic grouping only: collapse concrete owner arguments
    # and overload suffixes while preserving the owner/method separator.
    private def method_family_prefix(symbol : String) : String
      separator_index : Int32? = nil
      separator_byte = 0_u8
      suffix_index : Int32? = nil
      index = 0
      while index < symbol.bytesize
        byte = symbol.to_unsafe[index]
        if byte == '#'.ord.to_u8
          separator_index = index
          separator_byte = byte
        elsif byte == '.'.ord.to_u8
          unless separator_index
            separator_index = index
            separator_byte = byte
          end
        elsif byte == '$'.ord.to_u8
          suffix_index = index
          break
        end
        index += 1
      end

      unless separator = separator_index
        base = suffix_index ? symbol.byte_slice(0, suffix_index) : symbol
        return generic_namespace_family(base)
      end

      owner = symbol.byte_slice(0, separator)
      method_end = suffix_index || symbol.bytesize
      method = symbol.byte_slice(separator + 1, method_end - separator - 1)
      separator_text = separator_byte == '#'.ord.to_u8 ? "#" : "."
      "#{generic_namespace_family(owner)}#{separator_text}#{method}"
    end

    private def generic_namespace_family(owner : String) : String
      return owner unless owner.includes?('(')

      String.build(owner.bytesize) do |io|
        depth = 0
        index = 0
        while index < owner.bytesize
          byte = owner.to_unsafe[index]
          if byte == '('.ord.to_u8
            depth += 1
          elsif byte == ')'.ord.to_u8
            depth -= 1 if depth > 0
          elsif depth == 0
            io << byte.unsafe_chr
          end
          index += 1
        end
      end
    end

    private def symbol_event?(event_id : UInt16) : Bool
      event_id >= TraceFormat::Event::QueueEnqueue.value &&
        event_id <= TraceFormat::Event::MaterializeDone.value
    end

    private def concrete_registration_event?(event_id : UInt16) : Bool
      event_id == TraceFormat::Event::ConcreteRegisterStart.value ||
        event_id == TraceFormat::Event::ConcreteRegisterPoint.value ||
        event_id == TraceFormat::Event::ConcreteRegisterDone.value
    end

    private def nested_registration_event?(event_id : UInt16) : Bool
      event_id == TraceFormat::Event::NestedRegisterStart.value ||
        event_id == TraceFormat::Event::NestedRegisterDone.value
    end

    private def site_symbol_event?(event_id : UInt16) : Bool
      concrete_registration_event?(event_id) ||
        nested_registration_event?(event_id) ||
        event_id == TraceFormat::Event::VirtualTargetRecord.value ||
        event_id == TraceFormat::Event::VirtualTargetReplay.value
    end

    private def lower_request_event?(event_id : UInt16) : Bool
      event_id == TraceFormat::Event::LowerRequest.value ||
        event_id == TraceFormat::Event::LowerRequestEdge.value ||
        event_id == TraceFormat::Event::LowerRequestSite.value
    end

    private def read_header_at(io : File, offset : Int64, file_size : Int64) : ChunkHeader?
      return nil if file_size - offset < TraceFormat::CHUNK_HEADER_BYTES
      bytes = Bytes.new(TraceFormat::CHUNK_HEADER_BYTES)
      io.seek(offset)
      io.read_fully(bytes)
      return nil unless read_u32(bytes, 0) == TraceFormat::CHUNK_MAGIC
      return nil unless read_u16(bytes, 4) == TraceFormat::FORMAT_VERSION

      kind = read_u16(bytes, 6)
      payload_bytes = read_u32(bytes, 8)
      item_count = read_u32(bytes, 12)
      first_sequence = read_u64(bytes, 16)
      return nil unless kind >= TraceFormat::CHUNK_RUN && kind <= TraceFormat::CHUNK_SUMMARY
      framing_bytes = TraceFormat::CHUNK_HEADER_BYTES + TraceFormat::CHUNK_FOOTER_BYTES
      return nil if payload_bytes.to_i64 > file_size - offset - framing_bytes
      return nil unless valid_shape?(kind, payload_bytes, item_count, first_sequence)
      ChunkHeader.new(kind, payload_bytes, item_count, first_sequence)
    end

    private def valid_footer_at(
      io : File,
      offset : Int64,
      header : ChunkHeader,
      file_size : Int64,
    ) : Bool
      return false if file_size - offset < TraceFormat::CHUNK_FOOTER_BYTES
      bytes = Bytes.new(TraceFormat::CHUNK_FOOTER_BYTES)
      io.seek(offset)
      io.read_fully(bytes)
      read_u32(bytes, 0) == TraceFormat::CHUNK_FOOTER_MAGIC &&
        read_u16(bytes, 4) == TraceFormat::FORMAT_VERSION &&
        read_u16(bytes, 6) == header.kind &&
        read_u32(bytes, 8) == header.payload_bytes &&
        read_u32(bytes, 12) == header.item_count &&
        read_u64(bytes, 16) == header.first_sequence
    end

    private def valid_shape?(
      kind : UInt16,
      payload_bytes : UInt32,
      item_count : UInt32,
      first_sequence : UInt64,
    ) : Bool
      case kind
      when TraceFormat::CHUNK_RUN
        payload_bytes == 32_u32 && item_count == 1_u32 && first_sequence == 0_u64
      when TraceFormat::CHUNK_SYMBOLS
        payload_bytes.to_u64 >= item_count.to_u64 * 12_u64
      when TraceFormat::CHUNK_EVENTS
        payload_bytes.to_u64 == item_count.to_u64 * TraceFormat::EVENT_RECORD_BYTES.to_u64
      when TraceFormat::CHUNK_SUMMARY
        payload_bytes == 40_u32 && item_count == 1_u32
      else
        false
      end
    end

    private def find_next_run(io : File, start : Int64, file_size : Int64) : Int64?
      scan = Bytes.new(64 * 1024)
      absolute = start
      seen = 0
      window = 0_u32
      while absolute < file_size
        io.seek(absolute)
        readable = Math.min(scan.size.to_i64, file_size - absolute).to_i
        read = io.read(scan[0, readable])
        break if read == 0
        read.times do |index|
          window = (window >> 8) | (scan[index].to_u32 << 24)
          seen += 1
          next if seen < 4 || window != TraceFormat::CHUNK_MAGIC

          candidate = absolute + index - 3
          if header = read_header_at(io, candidate, file_size)
            footer_offset = candidate + TraceFormat::CHUNK_HEADER_BYTES + header.payload_bytes.to_i64
            if header.kind == TraceFormat::CHUNK_RUN &&
               valid_footer_at(io, footer_offset, header, file_size)
              return candidate
            end
          end
        end
        absolute += read
      end
      nil
    end

    private def read_u16(bytes : Bytes, offset : Int32) : UInt16
      bytes[offset].to_u16 | (bytes[offset + 1].to_u16 << 8)
    end

    private def read_u32(bytes : Bytes, offset : Int32) : UInt32
      value = 0_u32
      4.times { |index| value |= bytes[offset + index].to_u32 << (index * 8) }
      value
    end

    private def read_u64(bytes : Bytes, offset : Int32) : UInt64
      value = 0_u64
      8.times { |index| value |= bytes[offset + index].to_u64 << (index * 8) }
      value
    end

    private def format_ms(nanoseconds : UInt64) : String
      whole = nanoseconds // 1_000_000_u64
      fraction = (nanoseconds % 1_000_000_u64) // 1_000_u64
      "#{whole}.#{fraction.to_s.rjust(3, '0')}"
    end
  end

  private def self.usage : NoReturn
    STDERR.puts "Usage: crystal run scripts/analyze_lowering_trace.cr -- TRACE_FILE [--top N] [--tail N] [--virtual-target-match TEXT] [--event-window SEQUENCE:RADIUS] [--event-match TEXT]"
    exit 2
  end

  path = ARGV.shift? || usage
  top = 20
  tail = 40
  virtual_target_match = nil.as(String?)
  event_window = nil.as(Tuple(UInt32, Int32)?)
  event_match = nil.as(String?)
  until ARGV.empty?
    case option = ARGV.shift
    when "--top"
      top = (ARGV.shift? || usage).to_i
    when "--tail"
      tail = (ARGV.shift? || usage).to_i
    when "--virtual-target-match"
      virtual_target_match = ARGV.shift? || usage
    when "--event-window"
      parts = (ARGV.shift? || usage).split(':', 2)
      usage unless parts.size == 2
      sequence = parts[0].to_u32? || usage
      radius = parts[1].to_i? || usage
      usage if sequence == 0 || radius < 0
      event_window = {sequence, radius}
    when "--event-match"
      event_match = ARGV.shift? || usage
    else
      STDERR.puts "Unknown option: #{option}"
      usage
    end
  end
  usage if top < 0 || tail < 0

  analyzer = LoweringTraceAnalyzer.new(path)
  analyzer.parse
  analyzer.print_summary(top, tail, virtual_target_match, event_window, event_match)
end
