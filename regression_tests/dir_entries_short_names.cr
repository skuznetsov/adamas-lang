# Repro: Dir.entries previously returned empty strings or truncated names
# because LibC::Dirent.d_name (StaticArray(Char, 256)) was C-aligned to 8
# instead of 1. This put d_name at offset 24 instead of the correct C
# offset 21, shifting every name read 3 bytes past its actual start.
# Verifies the C ABI alignment of StaticArray(Char, N) in `lib` blocks.
# EXPECT: ok
require "c/dirent"

dir = LibC.opendir("/")
seen_short = false
short_count = 0
50.times do
  entry = LibC.readdir(dir)
  break if entry.null?
  e = entry.value
  ptr = e.d_name.to_unsafe.as(UInt8*)
  # Read the first byte of d_name — if alignment is off by 3, every name
  # appears truncated or empty for short names like "." or "..".
  first_byte = ptr[0]
  if first_byte != 0
    short_count += 1
    seen_short = true if first_byte == 46_u8 # '.'
  end
end
LibC.closedir(dir)

# After fix: at minimum "." should be visible and short_count > 0.
if seen_short && short_count > 0
  puts "ok"
else
  puts "fail: seen_short=#{seen_short} short_count=#{short_count}"
end
