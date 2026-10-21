lib C
  fun putchar(value : Int32) : Int32
end

struct DirectOuter
  struct DirectInner
    def self.marker : Int32
      65
    end

    def marker : Int32
      65
    end
  end
end

def consume_direct_inner(value : DirectOuter::DirectInner) : Int32
  value.marker
end

C.putchar(DirectOuter::DirectInner.marker)
C.putchar(consume_direct_inner(DirectOuter::DirectInner.new))
