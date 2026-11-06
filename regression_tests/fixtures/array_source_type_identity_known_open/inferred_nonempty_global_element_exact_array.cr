lib FixtureExit
  fun exit(status : Int32) : NoReturn
end
fun __crystal_raise_overflow : NoReturn
  FixtureExit.exit(87)
end

struct Pointer(T)
  def []=(offset : Int32, value : T)
    (self + offset.to_i64).value = value
  end
end

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

class Concrete
end

module LavinMQ
  module HTTP
    class Concrete
    end

    class Probe
      def self.run
        ::HTTP::Server.accept([::Concrete.new])
      end
    end
  end
end

module HTTP
  class Server
    def self.accept(items : Array(::Concrete))
      65
    end
  end
end

lib C
  fun putchar(value : Int32) : Int32
end

C.putchar(LavinMQ::HTTP::Probe.run)
C.putchar(10)
