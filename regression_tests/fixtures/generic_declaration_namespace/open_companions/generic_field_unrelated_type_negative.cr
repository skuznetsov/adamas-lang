@[Link("c")]
lib NamespaceFieldOutput
  fun putchar(value : Int32) : Int32
end

module Other
  struct Entry(T)
    @value : Int32

    def initialize(@value : Int32)
    end

    def value : Int32
      @value
    end
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

NamespaceFieldOutput.putchar(Box(Int32).new(Other::Entry(Int32).new(65)).value)
