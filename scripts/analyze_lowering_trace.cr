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
    duration_ns : UInt64,
    self_ns : UInt64,
    depth : UInt16,
    start_sequence : UInt32

  private class ActiveMaterialization
    getter event : TraceEvent
    property child_ns : UInt64

    def initialize(@event : TraceEvent)
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

    def print_summary(top : Int32, tail : Int32) : Nil
      puts "trace=#{@path} runs=#{@runs.size} recovered_segments=#{@recovered_segments} truncated_tail=#{@truncated_tail ? 1 : 0}"
      @runs.each do |run|
        print_run(run, top, tail)
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

    private def print_run(run : TraceRun, top : Int32, tail : Int32) : Nil
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
      active_materializations = [] of ActiveMaterialization
      materializations = [] of MaterializationSample
      unmatched_materializations = 0
      processes = [] of PhaseSample
      passes = [] of PhaseSample
      phase_events = [] of TraceEvent
      active_process : TraceEvent? = nil
      process_requests = 0
      process_materializations = 0
      active_pass : TraceEvent? = nil
      pass_requests = 0
      pass_materializations = 0
      request_profile_enabled = run.events.any? do |event|
        event.event_id == TraceFormat::Event::LowerRequestProfile.value
      end
      active_profile_requests = [] of TraceEvent
      request_profiles = [] of RequestProfileSample
      unmatched_request_profiles = 0
      run.events.each do |event|
        event_counts[event_name(event.event_id)] += 1
        if symbol = event.symbol
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
          end
        when TraceFormat::Event::MaterializeStart.value
          active_materializations << ActiveMaterialization.new(event)
        when TraceFormat::Event::MaterializeDone.value
          if active = active_materializations.pop?
            started = active.event
            if symbol = event.symbol
              if symbol == started.symbol
                duration_ns = event.delta_ns - started.delta_ns
                self_ns = duration_ns >= active.child_ns ? duration_ns - active.child_ns : 0_u64
                materializations << MaterializationSample.new(
                  symbol,
                  duration_ns,
                  self_ns,
                  event.depth,
                  started.sequence,
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
        when TraceFormat::Event::MissingStart.value,
             TraceFormat::Event::MissingIterStart.value,
             TraceFormat::Event::MissingScanDone.value,
             TraceFormat::Event::MissingIterDone.value,
             TraceFormat::Event::MissingDone.value
          phase_events << event
        end
      end
      unmatched_materializations += active_materializations.size
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

      edges = request_edges.to_a.sort_by do |(caller, callee), count|
        {-count, caller, callee}
      end.first(top)
      puts "  hot_request_edges:"
      edges.each do |(caller, callee), count|
        puts "    #{count.to_s.rjust(8)}  #{caller} -> #{callee}"
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
        puts "    total_ms=#{format_ms(sample.duration_ns).rjust(12)} self_ms=#{format_ms(sample.self_ns).rjust(12)} depth=#{sample.depth} seq=#{sample.start_sequence}  #{sample.symbol}"
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

      return if tail <= 0
      puts "  tail:"
      run.events.last(tail).each do |event|
        target = event.symbol || numeric_value(event)
        edge = event.caller ? " caller=#{event.caller}" : ""
        puts "    seq=#{event.sequence} delta_ms=#{format_ms(event.delta_ns)} depth=#{event.depth} event=#{event_name(event.event_id)} value=#{target}#{edge}"
      end
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

    private def symbol_event?(event_id : UInt16) : Bool
      event_id >= TraceFormat::Event::QueueEnqueue.value &&
        event_id <= TraceFormat::Event::MaterializeDone.value
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
    STDERR.puts "Usage: crystal run scripts/analyze_lowering_trace.cr -- TRACE_FILE [--top N] [--tail N]"
    exit 2
  end

  path = ARGV.shift? || usage
  top = 20
  tail = 40
  until ARGV.empty?
    case option = ARGV.shift
    when "--top"
      top = (ARGV.shift? || usage).to_i
    when "--tail"
      tail = (ARGV.shift? || usage).to_i
    else
      STDERR.puts "Unknown option: #{option}"
      usage
    end
  end
  usage if top < 0 || tail < 0

  analyzer = LoweringTraceAnalyzer.new(path)
  analyzer.parse
  analyzer.print_summary(top, tail)
end
