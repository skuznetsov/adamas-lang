lib LibC
  fun exit(status : Int32) : NoReturn
end

struct Info(T)
  getter value : T

  def initialize(@value : T)
  end
end

def make(value)
  Info.new(value: value)
end

def read_u32 : UInt32
  make(4294967295_u32).value
end

def read_u64 : UInt64
  make(4294967296_u64).value
end

u32 = read_u32
u64 = read_u64
expected_u32 = 4294967294_u32 + 1_u32
expected_u64 = 2147483648_u64 + 2147483648_u64
LibC.exit((u32 == expected_u32 && u64 == expected_u64) ? 0 : 1)
