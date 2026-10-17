# Regression: gets / read / read_byte / peek interleaved on ONE IO must consume
# the stream in program order (shared IO::Buffered in-buffer), for a File and
# for STDIN fed through a pipe. Remainder and EOF are checked at the end.
# Expected output is produced by the original Crystal compiler. Every line is
# written with a single-argument print so the check does not depend on
# IO#print(*objects) splat lowering.
# `exercise` takes an unrestricted `io` (one instantiation per concrete IO) and
# the File is not closed explicitly, so the check does not depend on two
# separate paths: virtual IO#read(Slice) and File#close. The former has its own
# JSON Escape/ordinary virtual-read regression; File#close remains an open bug.

def show(label : String, s : String?)
  if s
    STDOUT.print "#{label}=[#{s}] bs=#{s.bytesize} sz=#{s.size}\n"
  else
    STDOUT.print "#{label}=nil\n"
  end
end

def show_bytes(label : String, slice : Bytes, n : Int32)
  STDOUT.print "#{label}=#{n}:[#{String.new(slice[0, n])}]\n"
end

def show_byte(label : String, b : UInt8?)
  if b
    STDOUT.print "#{label}=#{b.chr}\n"
  else
    STDOUT.print "#{label}=nil\n"
  end
end

def exercise(tag : String, io)
  show "#{tag}.gets1", io.gets
  buf = Bytes.new(3)
  show_bytes "#{tag}.read3", buf, io.read(buf)
  show_byte "#{tag}.byte1", io.read_byte
  show "#{tag}.gets2", io.gets
  show "#{tag}.gets3", io.gets(chomp: false)
  show_byte "#{tag}.byte2", io.read_byte
  show_byte "#{tag}.byte3", io.read_byte
  show "#{tag}.gets_t", io.gets('t')
  show "#{tag}.gets4", io.gets
  show "#{tag}.gets_crlf", io.gets
  long = io.gets
  if long
    STDOUT.print "#{tag}.long bs=#{long.bytesize} head=#{long[0, 4]} tail=#{long[-4, 4]}\n"
  else
    STDOUT.print "#{tag}.long=nil\n"
  end
  peek = io.peek
  STDOUT.print "#{tag}.peek_nonempty=#{!!(peek && !peek.empty?)}\n"
  big = Bytes.new(20)
  show_bytes "#{tag}.read20", big, io.read(big)
  show "#{tag}.rest", io.gets_to_end
  show "#{tag}.eof_gets", io.gets
  show_byte "#{tag}.eof_byte", io.read_byte
  STDOUT.print "#{tag}.eof_read=#{io.read(buf)}\n"
end

path = ARGV[0]
file = File.new(path)
exercise("file", file)

exercise("stdin", STDIN)
STDOUT.flush
