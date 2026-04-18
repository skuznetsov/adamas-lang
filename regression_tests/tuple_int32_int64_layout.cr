# Regression: Tuple(Int32, Int64) element read/write must share aligned offsets.
# Guards against the Channel(Int64)#receive_internal bit-pack corruption bug:
#   https://memory/channel_buffered_receive_status.md (2026-04-18)
# Root cause: HIR try_coerce_tuple_to_tuple computed element offsets with
#   no alignment padding (elem1 @ offset 4) while MIR lower_allocate stored
#   aligned (elem1 @ offset 8). The size mismatch produced (payload_low32 << 32) | 1.
#
# Minimum trigger via Channel (buffered receive goes through receive_internal's
# Tuple(DeliveryState, T | UseDefault) return, exercising try_coerce_tuple_to_tuple).

ch = Channel(Int64).new(1)
ch.send(42_i64)
v = ch.receive
if v == 42_i64
  puts "tuple_int32_int64_layout_ok"
else
  puts "tuple_int32_int64_layout_FAIL got=#{v}"
end

ch2 = Channel(Int64).new(1)
ch2.send(1229782938247303441_i64)
v2 = ch2.receive
if v2 == 1229782938247303441_i64
  puts "tuple_int32_int64_layout_big_ok"
else
  puts "tuple_int32_int64_layout_big_FAIL got=#{v2}"
end
