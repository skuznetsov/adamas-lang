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
  module Nested
    struct Entry(U)
      def initialize(@value : Int32)
      end

      def value : Int32
        91
      end
    end

    class ::Box(T)
      def nested_reopened_entry : Entry(T)
        Entry(T).new(66)
      end
    end

    class Owner
      @box : ::Box(Int32) = ::Box(Int32).new(::Box::Entry(Int32).new(66))

      def value : Int32
        @box.nested_reopened_entry.value
      end
    end
  end
end

NamespaceOutput.putchar(Reopening::Nested::Owner.new.value)
