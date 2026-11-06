module Indexable(T)
end

class Array(T)
  include Indexable(T)
end

module HTTP
  module Handler
  end

  class Server
    def self.accept(items : Indexable(Handler))
      65
    end
  end
end

module LavinMQ
  module HTTP
    module Handler
    end

    class Probe
      def self.run
        ::HTTP::Server.accept([] of ::HTTP::Handler)
      end
    end
  end
end

lib C
  fun putchar(value : Int32) : Int32
end

C.putchar(LavinMQ::HTTP::Probe.run)
C.putchar(10)
