@[Link("c")]
lib NamespaceOutput
  fun putchar(value : Int32) : Int32
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

  def initialize(@entry : Entry(T))
  end

  def entry : Entry(T)
    @entry
  end
end

module Caller
  struct Entry(T)
    def initialize(@value : Int32)
    end

    def value : Int32
      90
    end
  end

  class Owner
    @box : ::Box(Int32) = ::Box(Int32).new(::Box::Entry(Int32).new(65))

    def value : Int32
      @box.entry.value
    end
  end
end

NamespaceOutput.putchar(Caller::Owner.new.value)
