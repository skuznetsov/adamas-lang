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
  end
end

LibC.exit(Domain::Sink.take(Owner) == 7 ? 0 : 1)
