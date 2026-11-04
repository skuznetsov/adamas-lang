lib LibC
  fun exit(status : Int32) : NoReturn
end

class ParentSink
  def self.take(value : Class, level : Int32 = 19) : Int32
    level
  end

  def self.take(value : Owner.class, level : Int32 = 23) : Int32
    level
  end

  def self.take(value : Owner, level : Int32 = 29) : Int32
    level
  end
end

class Sink < ParentSink
  def self.take(value : Bool) : Int32
    31
  end
end

class Owner
  VALUE = Sink.take(self)
  INSTANCE = Sink.take(new)
end

class Other
  VALUE = Sink.take(self)
end

LibC.exit(1) unless Owner::VALUE == 23
LibC.exit(2) unless Other::VALUE == 19
LibC.exit(3) unless Owner::INSTANCE == 29
LibC.exit(4) unless Sink.take(true) == 31
LibC.exit(0)
