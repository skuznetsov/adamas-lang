lib LibC
  fun exit(status : Int32) : NoReturn
end

class Owner
end

module Domain
  class Class
  end

  class Sink
    def self.take(value : Class) : Int32
      7
    end

    def self.take(value : ::Class) : Int32
      11
    end
  end
end

LibC.exit(1) unless Domain::Sink.take(Owner) == 11
LibC.exit(2) unless Domain::Sink.take(Domain::Class.new) == 7
LibC.exit(0)
