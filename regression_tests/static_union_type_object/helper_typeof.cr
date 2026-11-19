@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

def value(flag : Bool) : Bool | Int32
  Output.putchar(88)
  flag ? false : 7
end

def union_type_object
  typeof(value(true))
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

pick(union_type_object)
Output.putchar(10)
