lib LibC
  fun exit(status : Int32) : NoReturn
end

class Sink
  def self.take(value : Owner.class) : Int32
    7
  end
end

class Other
end

class Owner
  VALUE = Sink.take(Other)
end

LibC.exit(Owner::VALUE == 7 ? 0 : 1)
