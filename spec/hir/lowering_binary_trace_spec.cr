require "../spec_helper"
require "../../src/compiler/hir/lowering_binary_trace"

private record ParsedLoweringTraceEvent,
  run_index : Int32,
  sequence : UInt32,
  delta_ns : UInt64,
  event_id : UInt16,
  depth : UInt16,
  caller : String?,
  symbol : String

private record ParsedLoweringTrace,
  run_count : Int32,
  events : Array(ParsedLoweringTraceEvent),
  recovered_segments : Int32,
  truncated_tail : Bool

private def lowering_trace_footer_valid?(
  io : File,
  offset : Int64,
  size : Int64,
  kind : UInt16,
  payload_bytes : UInt32,
  item_count : UInt32,
  first_sequence : UInt64,
) : Bool
  return false if size - offset < Adamas::HIR::LoweringBinaryTrace::CHUNK_FOOTER_BYTES

  io.seek(offset)
  magic = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
  version = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
  footer_kind = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
  footer_payload_bytes = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
  footer_item_count = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
  footer_first_sequence = io.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
  magic == Adamas::HIR::LoweringBinaryTrace::CHUNK_FOOTER_MAGIC &&
    version == Adamas::HIR::LoweringBinaryTrace::FORMAT_VERSION &&
    footer_kind == kind &&
    footer_payload_bytes == payload_bytes &&
    footer_item_count == item_count &&
    footer_first_sequence == first_sequence
end

private def append_interrupted_lowering_event_chunk(path : String) : Nil
  File.open(path, "ab") do |io|
    io.write_bytes(Adamas::HIR::LoweringBinaryTrace::CHUNK_MAGIC, IO::ByteFormat::LittleEndian)
    io.write_bytes(Adamas::HIR::LoweringBinaryTrace::FORMAT_VERSION, IO::ByteFormat::LittleEndian)
    io.write_bytes(Adamas::HIR::LoweringBinaryTrace::CHUNK_EVENTS, IO::ByteFormat::LittleEndian)
    io.write_bytes(48_u32, IO::ByteFormat::LittleEndian)
    io.write_bytes(2_u32, IO::ByteFormat::LittleEndian)
    io.write_bytes(4_u64, IO::ByteFormat::LittleEndian)

    io.write_bytes(14_u64, IO::ByteFormat::LittleEndian)
    io.write_bytes(1_u64, IO::ByteFormat::LittleEndian)
    packed = 4_u64 |
             (Adamas::HIR::LoweringBinaryTrace::Event::QueueVisit.value.to_u64 << 32) |
             (1_u64 << 48)
    io.write_bytes(packed, IO::ByteFormat::LittleEndian)
  end
end

private def find_next_lowering_run_chunk(io : File, start : Int64, size : Int64) : Int64?
  header = Bytes.new(Adamas::HIR::LoweringBinaryTrace::CHUNK_HEADER_BYTES)
  candidate = start
  while candidate + header.size <= size
    io.seek(candidate)
    io.read_fully(header)
    header_io = IO::Memory.new(header)
    magic = header_io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
    version = header_io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
    kind = header_io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
    payload_bytes = header_io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
    item_count = header_io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
    first_sequence = header_io.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
    if magic == Adamas::HIR::LoweringBinaryTrace::CHUNK_MAGIC &&
       version == Adamas::HIR::LoweringBinaryTrace::FORMAT_VERSION &&
       kind == Adamas::HIR::LoweringBinaryTrace::CHUNK_RUN &&
       payload_bytes == 32_u32 &&
       item_count == 1_u32 &&
       first_sequence == 0_u64 &&
       candidate + header.size + payload_bytes + Adamas::HIR::LoweringBinaryTrace::CHUNK_FOOTER_BYTES <= size &&
       lowering_trace_footer_valid?(
         io,
         candidate + header.size + payload_bytes,
         size,
         kind,
         payload_bytes,
         item_count,
         first_sequence,
       )
      return candidate
    end
    candidate += 1
  end
  nil
end

private def parse_lowering_binary_trace(path : String) : ParsedLoweringTrace
  events = [] of ParsedLoweringTraceEvent
  symbols = {} of UInt64 => String
  run_index = -1
  recovered_segments = 0
  truncated_tail = false

  File.open(path, "rb") do |io|
    size = io.size
    while io.pos < size
      chunk_start = io.pos
      if size - io.pos < Adamas::HIR::LoweringBinaryTrace::CHUNK_HEADER_BYTES
        truncated_tail = true
        break
      end

      magic = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
      version = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
      kind = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
      payload_bytes = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
      item_count = io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
      first_sequence = io.read_bytes(UInt64, IO::ByteFormat::LittleEndian)

      unless magic == Adamas::HIR::LoweringBinaryTrace::CHUNK_MAGIC &&
             version == Adamas::HIR::LoweringBinaryTrace::FORMAT_VERSION
        if next_run = find_next_lowering_run_chunk(io, chunk_start + 1, size)
          recovered_segments += 1
          io.seek(next_run)
          next
        else
          truncated_tail = true
          break
        end
      end
      if size - io.pos < payload_bytes + Adamas::HIR::LoweringBinaryTrace::CHUNK_FOOTER_BYTES
        if next_run = find_next_lowering_run_chunk(io, chunk_start + 1, size)
          recovered_segments += 1
          io.seek(next_run)
          next
        else
          truncated_tail = true
          break
        end
      end

      footer_offset = io.pos + payload_bytes
      unless lowering_trace_footer_valid?(
               io,
               footer_offset,
               size,
               kind,
               payload_bytes,
               item_count,
               first_sequence,
             )
        if next_run = find_next_lowering_run_chunk(io, chunk_start + 1, size)
          recovered_segments += 1
          io.seek(next_run)
          next
        else
          truncated_tail = true
          break
        end
      end

      io.seek(chunk_start + Adamas::HIR::LoweringBinaryTrace::CHUNK_HEADER_BYTES)
      payload = Bytes.new(payload_bytes)
      io.read_fully(payload)
      io.seek(footer_offset + Adamas::HIR::LoweringBinaryTrace::CHUNK_FOOTER_BYTES)
      payload_io = IO::Memory.new(payload)
      case kind
      when Adamas::HIR::LoweringBinaryTrace::CHUNK_RUN
        run_index += 1
        symbols.clear
      when Adamas::HIR::LoweringBinaryTrace::CHUNK_SYMBOLS
        item_count.times do
          symbol_id = payload_io.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
          name_bytes = payload_io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
          name = Bytes.new(name_bytes)
          payload_io.read_fully(name)
          symbols[symbol_id] = String.new(name)
        end
      when Adamas::HIR::LoweringBinaryTrace::CHUNK_EVENTS
        item_count.times do |index|
          delta_ns = payload_io.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
          symbol_id = payload_io.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
          packed = payload_io.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
          sequence = (packed & 0xffff_ffff_u64).to_u32
          event_id = ((packed >> 32) & 0xffff_u64).to_u16
          depth = ((packed >> 48) & 0xffff_u64).to_u16
          sequence.should eq((first_sequence + index).to_u32)
          caller = nil.as(String?)
          symbol = ""
          if event_id == Adamas::HIR::LoweringBinaryTrace::Event::LowerRequestEdge.value
            caller = symbols[symbol_id & 0xffff_ffff_u64]?
            symbol = symbols[symbol_id >> 32]? || ""
          else
            symbol = symbols[symbol_id]? || ""
          end
          events << ParsedLoweringTraceEvent.new(
            run_index,
            sequence,
            delta_ns,
            event_id,
            depth,
            caller,
            symbol,
          )
        end
      end
    end
  end

  ParsedLoweringTrace.new(run_index + 1, events, recovered_segments, truncated_tail)
end

describe Adamas::HIR::LoweringBinaryTrace do
  it "appends interval chunks and preserves completed runs before a partial tail" do
    path = File.join(
      Dir.tempdir,
      "adamas_lowering_binary_trace_#{Process.pid}_#{Random.rand(1_000_000)}.bin",
    )

    begin
      first = Adamas::HIR::LoweringBinaryTrace.new(
        path,
        capacity_records: 8,
        flush_interval_ns: 10_u64,
        start_ticks: 1_000_u64,
      )
      first.record_symbol_at(
        Adamas::HIR::LoweringBinaryTrace::Event::QueueEnqueue,
        "Cycle#step$Int32",
        depth: 1,
        ticks: 1_005_u64,
      )
      first.record_symbol_at(
        Adamas::HIR::LoweringBinaryTrace::Event::QueueVisit,
        "Cycle#step$Int32",
        depth: 2,
        ticks: 1_010_u64,
      )
      first.record_request_at(
        "Cycle#step$Int32",
        "Cycle#work$String",
        depth: 2,
        ticks: 1_012_u64,
      )
      first.record_symbol_at(
        Adamas::HIR::LoweringBinaryTrace::Event::MaterializeDone,
        "Cycle#step$Int32",
        depth: 1,
        ticks: 1_013_u64,
      )
      first.close

      first_size = File.size(path)
      append_interrupted_lowering_event_chunk(path)

      second = Adamas::HIR::LoweringBinaryTrace.new(
        path,
        capacity_records: 8,
        flush_interval_ns: 10_u64,
        start_ticks: 2_000_u64,
      )
      second.record_symbol_at(
        Adamas::HIR::LoweringBinaryTrace::Event::LowerRequest,
        "Other#work",
        depth: 0,
        ticks: 2_004_u64,
      )
      second.close
      File.size(path).should be > first_size

      File.open(path, "ab") { |io| io.write(Bytes[0x41_u8, 0x44_u8, 0x54_u8]) }

      parsed = parse_lowering_binary_trace(path)
      parsed.run_count.should eq(2)
      parsed.recovered_segments.should eq(1)
      parsed.truncated_tail.should be_true
      parsed.events.map(&.symbol).should eq([
        "Cycle#step$Int32",
        "Cycle#step$Int32",
        "Cycle#work$String",
        "Cycle#step$Int32",
        "Other#work",
      ])
      parsed.events.map(&.caller).should eq([
        nil,
        nil,
        "Cycle#step$Int32",
        nil,
        nil,
      ])
      parsed.events.map(&.delta_ns).should eq([5_u64, 10_u64, 12_u64, 13_u64, 4_u64])
      parsed.events.map(&.sequence).should eq([1_u32, 2_u32, 3_u32, 4_u32, 1_u32])
      parsed.events.map(&.depth).should eq([1_u16, 2_u16, 2_u16, 1_u16, 0_u16])
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
