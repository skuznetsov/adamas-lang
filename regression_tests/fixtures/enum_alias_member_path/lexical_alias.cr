@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

lib NativeFlags
  enum RootOptions : UInt64
    Root = 0x08000000
  end

  enum LocalOptions : UInt64
    Local = 0x10000000
  end
end

module Exposed
  alias Options = NativeFlags::RootOptions
end

module Client
  module Exposed
    alias Options = NativeFlags::LocalOptions
  end

  def self.pick(value : NativeFlags::RootOptions) : Int32
    82
  end

  def self.pick(value : NativeFlags::LocalOptions) : Int32
    76
  end

  def self.print_result
    Output.putchar(pick(Exposed::Options::Local))
    Output.putchar(pick(::Exposed::Options::Root))
    Output.putchar(10)
  end
end

Client.print_result
