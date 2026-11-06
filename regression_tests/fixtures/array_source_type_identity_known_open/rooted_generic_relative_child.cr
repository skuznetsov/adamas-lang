module Indexable(T)
end

class Array(T)
  include Indexable(T)
end

class Box(T)
end

module LavinMQ
  module HTTP
    class Handler
    end

    class Box(T)
    end
  end
end

module HTTP
  class Server
    def self.accept(items : Indexable(::Box(::LavinMQ::HTTP::Handler)))
      65
    end
  end
end

module LavinMQ
  module HTTP
    class Probe
      def self.run
        ::HTTP::Server.accept([] of ::Box(Handler))
      end
    end
  end
end

lib C
  fun putchar(value : Int32) : Int32
end

C.putchar(LavinMQ::HTTP::Probe.run)
C.putchar(10)
