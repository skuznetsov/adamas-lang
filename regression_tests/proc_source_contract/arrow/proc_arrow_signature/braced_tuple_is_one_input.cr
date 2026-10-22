require "proc"

lib ProcSignatureRuntime
  fun putchar(value : Int32) : Int32
end

alias PairReader = {Int32, Int32} -> Int32
reader = PairReader.new { |pair| pair[1] }
ProcSignatureRuntime.putchar(reader.call({65_i32, 69_i32}))
ProcSignatureRuntime.putchar(10_i32)
