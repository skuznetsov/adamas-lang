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
        ::HTTP::Server.accept([] of Handler)
      end
    end
  end
end

LavinMQ::HTTP::Probe.run
