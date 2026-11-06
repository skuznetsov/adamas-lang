module Indexable(T)
end

class Array(T)
  include Indexable(T)
end

class GlobalThing
end

alias GlobalAlias = GlobalThing

module LavinMQ
  module HTTP
    class GlobalThing
    end

    alias GlobalAlias = GlobalThing
  end
end

module HTTP
  class Server
    def self.accept(items : Indexable(::GlobalThing?))
      65
    end
  end
end

module LavinMQ
  module HTTP
    class Probe
      def self.run
        ::HTTP::Server.accept([] of ::GlobalAlias?)
      end
    end
  end
end

lib C
  fun putchar(value : Int32) : Int32
end

C.putchar(LavinMQ::HTTP::Probe.run)
C.putchar(10)
