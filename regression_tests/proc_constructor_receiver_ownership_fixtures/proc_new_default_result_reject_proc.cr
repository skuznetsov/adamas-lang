require "proc"

struct Proc
  def self.new(marker : Int32, padding : Int32 = 0, &block : self) : Int32
    marker &+ padding
  end
end

def accept_proc(value : Proc(Int32, Int32)) : Int32
  value.call(0_i32)
end

accept_proc(Proc(Int32, Int32).new(67_i32) { |input| input })
