require "proc"

lib ProcSourceResultEdgeOracle
  fun putchar(value : Int32) : Int32
end

struct Proc
  def self.new(marker : Int32, padding : Int32 = 0, &block : self) : Int32
    marker &+ padding
  end
end

def accept_int32(value : Int32) : Int32
  value
end

values = {67_i32}
result = accept_int32(Proc(Int32, Int32).new(*values) { |input| input })
ProcSourceResultEdgeOracle.putchar(result)
ProcSourceResultEdgeOracle.putchar(10_i32)
