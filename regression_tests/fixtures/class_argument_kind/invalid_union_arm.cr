lib LibC
  fun exit(status : Int32) : NoReturn
end

class Owner
end

class Other
end

class Sink
  def self.take(value : Owner.class | Other) : Int32
    17
  end
end

LibC.exit(1) unless Sink.take(Owner.new) == 17
LibC.exit(2) unless Sink.take(Other.new) == 17
LibC.exit(0)
