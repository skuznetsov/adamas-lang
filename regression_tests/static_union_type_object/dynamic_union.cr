@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

def pick(x : Bool.class)
  Output.putchar(66)
end

def pick(x : Int32.class)
  Output.putchar(73)
end

def pick(x : (Bool | Int32).class)
  Output.putchar(85)
end

def metaclass(flag : Bool)
  flag ? Bool : Int32
end

pick(metaclass(true))
pick(metaclass(false))
Output.putchar(10)
