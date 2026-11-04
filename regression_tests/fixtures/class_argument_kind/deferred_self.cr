lib LibC
  fun exit(status : Int32) : NoReturn
end

class Sink
  def self.take(value : Class) : Int32
    7
  end
end

class Owner
  VALUE = Sink.take(self)
end

LibC.exit(Owner::VALUE == 7 ? 0 : 1)
