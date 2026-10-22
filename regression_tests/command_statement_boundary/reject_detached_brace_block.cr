lib LibC
  fun putchar(value : Int32) : Int32
end

def identity(value : Int32) : Int32
  value
end

identity 65
{ |value| LibC.putchar(value) }
