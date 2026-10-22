require "proc"

lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

class ProcBoundaryInt32Factory
  def self.new(&block : Int32 -> Int32) : Int32
    block.call(67_i32)
  end
end

value = ProcBoundaryInt32Factory.new { |input| input }
ProcContractRuntime.putchar(value)
ProcContractRuntime.putchar(10_i32)
