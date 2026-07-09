def make_bytes
  bytes = uninitialized UInt8[4]
  bytes[0] = 65_u8
  {bytes, 3}
end

bytes, count = make_bytes
raise "static array tuple return contract" unless bytes[0] == 65_u8 && count == 3
