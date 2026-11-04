lib LibC
  fun exit(status : Int32) : NoReturn
end

class OriginalError
end

class Stream
  class Error < OriginalError
    class Detail
      def self.code
        5
      end
    end

    def initialize(@code : Int32)
    end
  end
end

module Codec
  class Stream < ::Stream
  end

  alias Wrapped = Stream

  class Reader < ::Stream
    def read
      accept Stream::Error.new 7
    end

    def accept(error : OriginalError)
      3
    end
  end
end

module IncludedErrors
  class Retry
    def self.code
      6
    end
  end
end

class IncludedStream < ::Stream
  include IncludedErrors
end

class ShadowStream < ::Stream
  class Error
    class Detail
      def self.code
        8
      end
    end
  end
end

LibC.exit(12) unless Codec::Reader.new.read == 3
LibC.exit(13) unless ::Codec::Stream::Error::Detail.code() == 5
LibC.exit(14) unless ::Codec::Wrapped::Error::Detail.code == 5
LibC.exit(15) unless IncludedStream::Retry.code() == 6
LibC.exit(16) unless ::ShadowStream::Error::Detail.code() == 8
LibC.exit(0)
