lib LibC
  fun putchar(value : Int32) : Int32
end

def identity(value : Int32) : Int32
  value
end

identity 65
{answer: LibC.putchar(67), other: }
