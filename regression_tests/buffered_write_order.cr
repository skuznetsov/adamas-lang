# Regression: IO::FileDescriptor#write(Slice) must go through IO::Buffered#write.
# A backend syscall override wrote slices straight to the fd while write_byte and
# print(Char) filled the out buffer, so mixed byte/slice output was reordered
# (expected "payload\nAbyte\n", got "payload\nbyte\nA").

struct MatchingCasePayload
end

def only_byte(value : UInt8)
  STDOUT.write_byte(value)
  puts "byte"
end

def matching_case_probe(flag : Bool)
  value = flag ? MatchingCasePayload.new : 65_u8
  case value
  when UInt8
    only_byte(value)
  else
    puts "payload"
  end
end

def mixed_writes(io : IO)
  io.write_byte('a'.ord.to_u8)
  io.print "bc"
  io << 'd'
  io.write "ef".to_slice
  io.print 'g'
  io << "h" << 1 << '\n'
  io.print "no-newline:"
  io.write_byte('x'.ord.to_u8)
  io.print "y"
  io.write_byte('\n'.ord.to_u8)
end

matching_case_probe(true)
matching_case_probe(false)

mixed_writes(STDOUT)

print "tail-"
STDOUT.write_byte('z'.ord.to_u8)
print "!"
puts

mem = IO::Memory.new
mixed_writes(mem)
mem.write_byte('M'.ord.to_u8)
mem.print "end"
puts "memory=#{mem.to_s.inspect}"

path = ARGV[0]? || "buffered_write_order.out"
# File.new + flush instead of File.open(&block): closing a File currently crashes
# in IO::FileDescriptor#unbuffered_close, an unrelated bug. The fd stays open until exit.
file = File.new(path, "w")
mixed_writes(file)
file.write_byte('F'.ord.to_u8)
file.print "end"
file.flush
puts "file=#{File.read(path).inspect}"
File.delete(path)

# Slices larger than the 8 KiB out buffer and a slice that crosses the buffer remainder.
# Explicit parentheses: `write (expr).to_slice` hits a separate parser bug.
STDOUT.write_byte('<'.ord.to_u8)
STDOUT.write(("x" * 9000).to_slice)
STDOUT.write_byte('>'.ord.to_u8)
print "mid"
STDOUT.write(("y" * 8190).to_slice)
puts "|end"

STDERR.write_byte('E'.ord.to_u8)
STDERR.print "rr"
STDERR.write("!".to_slice)
STDERR.puts

print "final-no-newline"
STDOUT.write_byte('.'.ord.to_u8)

# Switching to sync mode must flush pending bytes first, then write through.
STDOUT.sync = true
STDOUT.write_byte('s'.ord.to_u8)
STDOUT.write("ync".to_slice)
print "-on"
