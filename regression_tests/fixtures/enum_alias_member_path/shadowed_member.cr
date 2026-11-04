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

  def self.read
    Exposed::Options::Root
  end
end

Client.read
