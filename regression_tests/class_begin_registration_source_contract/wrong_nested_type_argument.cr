lib C
  fun putchar(value : Int32) : Int32
end

macro nested_record(name)
  struct {{name.id}}
    def marker : Int32
      65
    end
  end
end

struct BeginArgumentOuter
  begin
    nested_record Inner
  end
end

def consume_begin_inner(value : BeginArgumentOuter::Inner) : Int32
  value.marker
end

C.putchar(consume_begin_inner(true))
