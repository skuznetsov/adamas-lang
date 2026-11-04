class Stream
  class Error
    def self.code
      5
    end
  end
end

module Codec
  class Stream
  end

  def self.read
    ::Codec::Stream::Error.code()
  end
end

Codec.read
