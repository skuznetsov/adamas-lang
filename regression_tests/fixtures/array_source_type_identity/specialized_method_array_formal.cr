class Array(T)
end

def build(value : T) : Array(T) forall T
  [] of T
end

def consume(items : Array(Int32))
  65
end

lib C
  fun putchar(value : Int32) : Int32
end
C.putchar(consume(build(0)))
C.putchar(10)
