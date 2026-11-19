@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

def value(flag : Bool) : Bool | Int32
  Output.putchar(88)
  flag ? false : 7
end

def accept(value : Bool.class | Int32.class)
  Output.putchar(65)
end

accept(typeof(value(true)))
Output.putchar(10)
