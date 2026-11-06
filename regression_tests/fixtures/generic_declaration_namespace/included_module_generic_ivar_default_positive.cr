@[Link("c")]
lib NamespaceOutput
  fun putchar(value : Int32) : Int32
end

module LexicalOwner
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

  module HasBox
    @box : Box(Int32) = Box(Int32).new(Box::Entry(Int32).new(67))

    def value : Int32
      @box.entry.value
    end
  end
end

module Caller
  class Box(T)
    struct Entry(U)
      def initialize(@value : Int32)
      end

      def value : Int32
        90
      end
    end
  end

  class Owner
    include LexicalOwner::HasBox
  end
end

NamespaceOutput.putchar(Caller::Owner.new.value)
