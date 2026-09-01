require "../bootstrap_shims"

module Adamas::HIR
  # Default-off append-only trace for diagnosing lowering worklist cycles.
  # The hot path writes fixed 24-byte records into a preallocated buffer.
  # Completed chunks remain readable when the final chunk is interrupted.
  class LoweringBinaryTrace
    CHUNK_MAGIC        = 0x4352_5441_u32 # "ATRC" in little-endian byte order
    CHUNK_FOOTER_MAGIC = 0x444E_4541_u32 # "AEND" in little-endian byte order
    FORMAT_VERSION     =           1_u16
    CHUNK_RUN          =           1_u16
    CHUNK_SYMBOLS      =           2_u16
    CHUNK_EVENTS       =           3_u16
    CHUNK_SUMMARY      =           4_u16
    CHUNK_HEADER_BYTES =              24
    CHUNK_FOOTER_BYTES =              24
    EVENT_RECORD_BYTES =              24

    DEFAULT_CAPACITY_RECORDS  =       1_048_576
    MAX_CAPACITY_RECORDS      =       8_388_608
    DEFAULT_FLUSH_INTERVAL_NS = 250_000_000_u64

    enum Event : UInt16
      ProcessStart     =  1
      PassStart        =  2
      QueueEnqueue     =  3
      QueueVisit       =  4
      LowerRequest     =  5
      MaterializeStart =  6
      MaterializeDone  =  7
      PassDone         =  8
      ProcessDone      =  9
      MissingStart     = 10
      MissingIterStart = 11
      MissingScanDone  = 12
      MissingIterDone  = 13
      MissingDone      = 14
    end

    getter dropped_events : UInt64
    getter flush_count : UInt64
    getter sequence : UInt32

    @path : String
    @flush_interval_ns : UInt64
    @start_ticks : UInt64
    @capacity_records : Int32
    @records : Slice(UInt64)
    @record_count : Int32
    @sequence : UInt32
    @dropped_events : UInt64
    @flush_count : UInt64
    @bytes_written : UInt64
    @write_time_ns : UInt64
    @last_flush_ticks : UInt64
    @symbol_ids : Hash(String, UInt64)
    @symbols : Array(String)
    @symbols_flushed : Int32
    @chunk_header : Bytes
    @chunk_footer : Bytes
    @fd : Int32
    @active : Bool

    def self.from_env : self?
      path = Adamas::Compiler::BootstrapEnv.get?("ADAMAS_HIR_BINARY_TRACE")
      return nil unless path
      return nil if path.empty?

      capacity = parse_bounded_env_int(
        "ADAMAS_HIR_BINARY_TRACE_CAPACITY",
        DEFAULT_CAPACITY_RECORDS,
        1_024,
        MAX_CAPACITY_RECORDS,
      )
      flush_ms = parse_bounded_env_int(
        "ADAMAS_HIR_BINARY_TRACE_FLUSH_MS",
        250,
        1,
        60_000,
      )
      new(path, capacity_records: capacity, flush_interval_ns: flush_ms.to_u64 * 1_000_000_u64)
    end

    private def self.parse_bounded_env_int(
      key : String,
      default : Int32,
      minimum : Int32,
      maximum : Int32,
    ) : Int32
      raw = Adamas::Compiler::BootstrapEnv.get?(key)
      return default unless raw
      value = raw.to_i?
      return default unless value
      return minimum if value < minimum
      return maximum if value > maximum
      value.to_i32
    end

    def initialize(
      @path : String,
      capacity_records : Int32 = DEFAULT_CAPACITY_RECORDS,
      @flush_interval_ns : UInt64 = DEFAULT_FLUSH_INTERVAL_NS,
      @start_ticks : UInt64 = Crystal::System::Time.ticks,
    )
      capacity_records = 1_024 if capacity_records < 1_024
      capacity_records = MAX_CAPACITY_RECORDS if capacity_records > MAX_CAPACITY_RECORDS
      @capacity_records = capacity_records
      @records = Slice(UInt64).new(@capacity_records * 3, 0_u64)
      @record_count = 0
      @sequence = 0_u32
      @dropped_events = 0_u64
      @flush_count = 0_u64
      @bytes_written = 0_u64
      @write_time_ns = 0_u64
      @last_flush_ticks = @start_ticks
      @symbol_ids = Hash(String, UInt64).new(initial_capacity: 4_096)
      @symbols = [] of String
      @symbols_flushed = 0
      @chunk_header = Bytes.new(CHUNK_HEADER_BYTES, 0_u8)
      @chunk_footer = Bytes.new(CHUNK_FOOTER_BYTES, 0_u8)
      @fd = -1
      @active = false
      begin
        @fd = LibC.open(
          @path.to_unsafe,
          LibC::O_WRONLY | LibC::O_CREAT | LibC::O_APPEND | LibC::O_CLOEXEC,
          0o644,
        )
        @active = @fd >= 0
        write_run_chunk if @active
      rescue
        disable
      end
    end

    def active? : Bool
      @active
    end

    def record(event : Event, value : UInt64 = 0_u64, depth : Int32 = 0) : Nil
      record_at(event, value, depth: depth, ticks: Crystal::System::Time.ticks)
    end

    def record_symbol(event : Event, symbol : String, depth : Int32 = 0) : Nil
      record_symbol_at(event, symbol, depth: depth, ticks: Crystal::System::Time.ticks)
    end

    # Explicit timestamps keep format and interval behavior directly testable
    # without sleeps or a bootstrap run.
    def record_symbol_at(
      event : Event,
      symbol : String,
      depth : Int32 = 0,
      ticks : UInt64 = Crystal::System::Time.ticks,
    ) : Nil
      return unless @active
      record_at(event, intern_symbol(symbol), depth: depth, ticks: ticks)
    end

    def record_at(
      event : Event,
      value : UInt64 = 0_u64,
      depth : Int32 = 0,
      ticks : UInt64 = Crystal::System::Time.ticks,
    ) : Nil
      unless @active
        @dropped_events &+= 1_u64
        return
      end

      flush_at(ticks) if @record_count >= @capacity_records
      unless @active
        @dropped_events &+= 1_u64
        return
      end

      @sequence &+= 1_u32
      delta_ns = ticks >= @start_ticks ? ticks - @start_ticks : 0_u64
      bounded_depth = if depth <= 0
                        0_u16
                      elsif depth >= UInt16::MAX
                        UInt16::MAX
                      else
                        depth.to_u16
                      end
      packed = @sequence.to_u64 |
               (event.value.to_u64 << 32) |
               (bounded_depth.to_u64 << 48)
      offset = @record_count * 3
      pointer = @records.to_unsafe + offset
      pointer[0] = delta_ns
      pointer[1] = value
      pointer[2] = packed
      @record_count += 1

      if @flush_interval_ns > 0_u64 &&
         ticks >= @last_flush_ticks &&
         ticks - @last_flush_ticks >= @flush_interval_ns
        flush_at(ticks)
      end
    end

    def flush : Nil
      flush_at(Crystal::System::Time.ticks)
    end

    def close : Nil
      return unless @active

      flush
      if @active
        summary = Bytes.new(40, 0_u8)
        put_u64(summary, 0, @sequence.to_u64)
        put_u64(summary, 8, @dropped_events)
        put_u64(summary, 16, @flush_count)
        put_u64(summary, 24, @bytes_written)
        put_u64(summary, 32, @write_time_ns)
        write_chunk(CHUNK_SUMMARY, summary, 1_u32, @sequence.to_u64)
      end
      if @fd >= 0
        LibC.close(@fd)
        @fd = -1
      end
      @active = false
    rescue
      disable
    end

    private def intern_symbol(symbol : String) : UInt64
      if existing = @symbol_ids[symbol]?
        return existing
      end

      symbol_id = @symbols.size.to_u64 + 1_u64
      @symbol_ids[symbol] = symbol_id
      @symbols << symbol
      symbol_id
    end

    private def flush_at(ticks : UInt64) : Nil
      return unless @active
      return if @record_count == 0

      started_at = Crystal::System::Time.ticks
      unless write_pending_symbols
        disable
        return
      end

      first_sequence = @sequence.to_u64 - @record_count.to_u64 + 1_u64
      payload_bytes = @record_count * EVENT_RECORD_BYTES
      payload = Bytes.new(
        @records.to_unsafe.as(Pointer(UInt8)),
        payload_bytes,
        read_only: true,
      )
      unless write_chunk(CHUNK_EVENTS, payload, @record_count.to_u32, first_sequence)
        disable
        return
      end

      @record_count = 0
      @flush_count &+= 1_u64
      @last_flush_ticks = ticks
      finished_at = Crystal::System::Time.ticks
      @write_time_ns &+= finished_at - started_at if finished_at >= started_at
    rescue
      disable
    end

    private def write_run_chunk : Nil
      payload = Bytes.new(32, 0_u8)
      put_u64(payload, 0, @start_ticks)
      put_u32(payload, 8, Process.pid.to_u32)
      put_u16(payload, 12, EVENT_RECORD_BYTES.to_u16)
      payload[14] = 1_u8 # little-endian records
      put_u32(payload, 16, @capacity_records.to_u32)
      put_u64(payload, 24, @flush_interval_ns)
      disable unless write_chunk(CHUNK_RUN, payload, 1_u32, 0_u64)
    end

    private def write_pending_symbols : Bool
      count = @symbols.size - @symbols_flushed
      return true if count <= 0

      payload_bytes = 0
      index = @symbols_flushed
      while index < @symbols.size
        payload_bytes += 12 + @symbols[index].bytesize
        index += 1
      end
      payload = Bytes.new(payload_bytes, 0_u8)
      offset = 0
      index = @symbols_flushed
      while index < @symbols.size
        symbol = @symbols[index]
        put_u64(payload, offset, index.to_u64 + 1_u64)
        put_u32(payload, offset + 8, symbol.bytesize.to_u32)
        offset += 12
        payload[offset, symbol.bytesize].copy_from(symbol.to_slice)
        offset += symbol.bytesize
        index += 1
      end

      return false unless write_chunk(
                            CHUNK_SYMBOLS,
                            payload,
                            count.to_u32,
                            @symbols_flushed.to_u64 + 1_u64,
                          )
      @symbols_flushed = @symbols.size
      true
    end

    private def write_chunk(
      kind : UInt16,
      payload : Bytes,
      item_count : UInt32,
      first_sequence : UInt64,
    ) : Bool
      @chunk_header.fill(0_u8)
      put_u32(@chunk_header, 0, CHUNK_MAGIC)
      put_u16(@chunk_header, 4, FORMAT_VERSION)
      put_u16(@chunk_header, 6, kind)
      put_u32(@chunk_header, 8, payload.size.to_u32)
      put_u32(@chunk_header, 12, item_count)
      put_u64(@chunk_header, 16, first_sequence)
      return false unless write_all(@chunk_header)
      return false unless write_all(payload)
      @chunk_footer.fill(0_u8)
      put_u32(@chunk_footer, 0, CHUNK_FOOTER_MAGIC)
      put_u16(@chunk_footer, 4, FORMAT_VERSION)
      put_u16(@chunk_footer, 6, kind)
      put_u32(@chunk_footer, 8, payload.size.to_u32)
      put_u32(@chunk_footer, 12, item_count)
      put_u64(@chunk_footer, 16, first_sequence)
      return false unless write_all(@chunk_footer)
      true
    end

    private def write_all(bytes : Bytes) : Bool
      offset = 0
      while offset < bytes.size
        written = LibC.write(@fd, bytes.to_unsafe + offset, bytes.size - offset)
        return false if written <= 0
        offset += written.to_i
        @bytes_written &+= written.to_u64
      end
      true
    end

    private def disable : Nil
      if @fd >= 0
        LibC.close(@fd)
        @fd = -1
      end
      @dropped_events &+= @record_count.to_u64
      @record_count = 0
      @active = false
    rescue
      @active = false
    end

    private def put_u16(bytes : Bytes, offset : Int32, value : UInt16) : Nil
      bytes[offset] = (value & 0xff_u16).to_u8
      bytes[offset + 1] = ((value >> 8) & 0xff_u16).to_u8
    end

    private def put_u32(bytes : Bytes, offset : Int32, value : UInt32) : Nil
      bytes[offset] = (value & 0xff_u32).to_u8
      bytes[offset + 1] = ((value >> 8) & 0xff_u32).to_u8
      bytes[offset + 2] = ((value >> 16) & 0xff_u32).to_u8
      bytes[offset + 3] = ((value >> 24) & 0xff_u32).to_u8
    end

    private def put_u64(bytes : Bytes, offset : Int32, value : UInt64) : Nil
      index = 0
      while index < 8
        bytes[offset + index] = ((value >> (index * 8)) & 0xff_u64).to_u8
        index += 1
      end
    end
  end
end
