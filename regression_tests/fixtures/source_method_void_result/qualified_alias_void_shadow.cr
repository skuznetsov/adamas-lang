lib C
  fun putchar(value : Int32) : Int32
end

module SourceVoidOwner
  alias ResultKind = Void

  class Worker
    def perform : ResultKind
      C.putchar(65) # A: method effect
      88
    end
  end
end

module SourceVoidCaller
  alias ResultKind = Int32

  def self.observe(value : Nil)
    C.putchar(78) # N: Nil overload
    nil
  end

  def self.observe(value : Int32)
    C.putchar(73) # I: Int32 overload
    nil
  end

  def self.run
    observe(SourceVoidOwner::Worker.new.perform)
  end
end

SourceVoidCaller.run
C.putchar(10)
