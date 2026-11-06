module Indexable(T)
end

class Array(T)
  include Indexable(T)

  @buffer : Pointer(T)

  def initialize
    @buffer = Pointer(T).new(0_u64)
  end

  def initialize(capacity : Int32)
    @buffer = Pointer(T).malloc(capacity.to_u64)
  end

  def self.unsafe_build(capacity : Int32) : self
    new(capacity)
  end

  def to_unsafe : Pointer(T)
    @buffer
  end
end

class Box(T)
end

module LavinMQ
  module HTTP
    class Handler
    end

    class Box(T)
    end

    class Probe
      def self.run
        ::HTTP::Server.accept([] of ::Box(Handler))
      end
    end
  end
end

module HTTP
  class Server
    def self.accept(items : Array(::Box(::LavinMQ::HTTP::Handler)))
      65
    end
  end
end

lib C
  fun putchar(value : Int32) : Int32
end

C.putchar(LavinMQ::HTTP::Probe.run)
C.putchar(10)
