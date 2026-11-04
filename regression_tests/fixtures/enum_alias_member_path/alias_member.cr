@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

lib NativeFlags
  enum Options : UInt64
    First = 0x08000000
    Second = 0x10000000
  end
end

module Exposed
  alias Options = NativeFlags::Options
  alias Renamed = Options
end

def pick_flag(value : NativeFlags::Options) : Int32
  65
end

def pick_flag(value : UInt64) : Int32
  88
end

Output.putchar(pick_flag(Exposed::Options::First))
Output.putchar(pick_flag(::Exposed::Renamed::Second))
Output.putchar(10)
