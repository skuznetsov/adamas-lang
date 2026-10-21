lib C
  fun putchar(value : Int32) : Int32
end

macro nested_record(name)
  struct {{name.id}}
    def self.marker : Int32
      65
    end

    def marker : Int32
      66
    end
  end
end

struct PlainBeginOuter
  begin
    nested_record Inner
    alias InnerAlias = Inner
    CLASS_MARKER = 67

    def self.outer_marker : Int32
      68
    end
  end
end

def consume_plain_begin_inner(value : PlainBeginOuter::InnerAlias) : Int32
  value.marker
end

C.putchar(PlainBeginOuter::Inner.marker)
C.putchar(consume_plain_begin_inner(PlainBeginOuter::InnerAlias.new))
C.putchar(PlainBeginOuter::CLASS_MARKER)
C.putchar(PlainBeginOuter.outer_marker)
