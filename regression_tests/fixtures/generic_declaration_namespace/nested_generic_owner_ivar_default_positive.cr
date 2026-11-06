@[Link("c")]
lib NamespaceOutput
  fun putchar(value : Int32) : Int32
end

module Lexical
  module Inner
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
  end
end

module Caller
  module Lexical
    module Inner
      struct Entry(T)
        def initialize(@value : Int32)
        end

        def value : Int32
          90
        end
      end

      class Owner
        @box : ::Lexical::Inner::Box(Int32) =
          ::Lexical::Inner::Box(Int32).new(::Lexical::Inner::Box::Entry(Int32).new(66))

        def value : Int32
          @box.entry.value
        end
      end
    end
  end
end

NamespaceOutput.putchar(Caller::Lexical::Inner::Owner.new.value)
