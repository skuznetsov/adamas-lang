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

module Reopening
  struct Entry(U)
    def initialize(@value : Int32)
    end

    def value : Int32
      90
    end
  end

  class ::Box(T)
    def reopened_entry : Entry(T)
      Entry(T).new(65)
    end
  end

  class Owner
    @box : ::Box(Int32) = ::Box(Int32).new(::Box::Entry(Int32).new(65))

    def value : Int32
      @box.reopened_entry.value
    end
  end
end

NamespaceOutput.putchar(Reopening::Owner.new.value)
