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

def value(flag : Bool) : Bool | Int32
  flag ? true : 7
end

pick(value(true))
