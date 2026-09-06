lib LibC
  fun exit(status : Int32) : NoReturn
end

module ReceiverIdentityA
  class Bag(T)
    def initialize
    end

    def <<(value : T)
      self
    end

    def marker : Int32
      10
    end
  end

  def self.relative : Bag(Int32)
    Bag{1}
  end

  def self.absolute : ::ReceiverIdentityA::Bag(Int32)
    ::ReceiverIdentityA::Bag{1}
  end
end

module ReceiverIdentityB
  class Bag(T)
    def initialize
    end

    def <<(value : T)
      self
    end

    def marker : Int32
      20
    end
  end

  def self.relative : Bag(Int32)
    Bag{1}
  end

  def self.absolute : ::ReceiverIdentityB::Bag(Int32)
    ::ReceiverIdentityB::Bag{1}
  end
end

LibC.exit(1) unless ReceiverIdentityA.relative.marker == 10
LibC.exit(2) unless ReceiverIdentityA.absolute.marker == 10
LibC.exit(3) unless ReceiverIdentityB.relative.marker == 20
LibC.exit(4) unless ReceiverIdentityB.absolute.marker == 20
LibC.exit(0)
