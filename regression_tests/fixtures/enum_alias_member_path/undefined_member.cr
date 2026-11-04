lib NativeFlags
  enum Options : UInt64
    First = 0x08000000
  end
end

module Exposed
  alias Options = NativeFlags::Options
end

Exposed::Options::Missing
