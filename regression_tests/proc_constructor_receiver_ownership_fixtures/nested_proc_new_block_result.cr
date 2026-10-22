require "proc"

lib DeferredProcResultOutput
  fun putchar(value : Int32) : Int32
end

struct Proc
  def self.new(&block : self)
    block.call(66_i32)
  end
end

def nested_int64_result
  inner_int64_result
end

def inner_int64_result
  Proc(Int32, Int64).new { |input| 66_i64 }
end

def nested_int32_result
  inner_int32_result
end

def inner_int32_result
  Proc(Int32, Int32).new { |input| 67_i32 }
end

int64_result = nested_int64_result
int32_result = nested_int32_result
DeferredProcResultOutput.putchar(int64_result.to_i32!)
DeferredProcResultOutput.putchar(int32_result)
DeferredProcResultOutput.putchar(10_i32)
