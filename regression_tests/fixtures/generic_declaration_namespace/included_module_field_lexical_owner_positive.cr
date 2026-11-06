@[Link("c")]
lib NamespaceFieldOutput
  fun putchar(value : Int32) : Int32
end

module LexicalOwner
  module Loop
    class Ar
      struct Idx
        @value : Int32

        def initialize(@value : Int32)
        end

        def value : Int32
          @value
        end
      end
    end
  end

  module HasEntry
    @entry : Loop::Ar::Idx

    def initialize(@entry : Loop::Ar::Idx)
    end

    def set_entry(value : Loop::Ar::Idx)
      @entry = value
    end

    def entry_value : Int32
      @entry.value
    end
  end
end

class IncludedHost
  module Loop
    class Ar
      struct Idx
        def initialize(@value : Int32)
        end

        def value : Int32
          90
        end
      end
    end
  end

  include LexicalOwner::HasEntry
end

host = IncludedHost.new(LexicalOwner::Loop::Ar::Idx.new(66))
host.set_entry(LexicalOwner::Loop::Ar::Idx.new(66))
NamespaceFieldOutput.putchar(host.entry_value)
