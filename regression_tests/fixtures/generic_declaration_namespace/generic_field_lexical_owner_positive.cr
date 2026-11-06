@[Link("c")]
lib NamespaceFieldOutput
  fun putchar(value : Int32) : Int32
end

module Caller
  struct Entry(T)
    @value : Int32

    def initialize(@value : Int32)
    end

    def value : Int32
      @value
    end
  end

  def self.build
    Box(Int32).new(Box::Entry(Int32).new(65))
  end
end

class Box(T)
  struct Entry(U)
    @value : Int32

    def initialize(@value : Int32)
    end

    def value : Int32
      @value
    end
  end

  @entry : Entry(T)

  def initialize(entry : Entry(T))
    @entry = entry
  end

  def value : Int32
    @entry.value
  end
end

NamespaceFieldOutput.putchar(Caller.build.value)
