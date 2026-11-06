lib C
  fun putchar(value : Int32) : Int32
end

class SourceVoidOverloadMarker
end

class SourceVoidOverloadOther
end

def choose(value : SourceVoidOverloadMarker) : Void
  C.putchar(67) # C: selected overload effect
  77
end

def choose(value : SourceVoidOverloadOther) : Int32
  C.putchar(68) # D: wrong sibling overload effect
  73
end

def observe(value : Nil)
  C.putchar(78) # N: Nil overload
end

def observe(value : Int32)
  C.putchar(73) # I: Int32 overload
end

observe(choose(SourceVoidOverloadMarker.new))
C.putchar(10)
