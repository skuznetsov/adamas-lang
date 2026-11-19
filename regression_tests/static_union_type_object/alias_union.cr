@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

alias Choice = Bool | Int32

def pick(x : Bool.class)
  Output.putchar(66)
end

def pick(x : Int32.class)
  Output.putchar(73)
end

def pick(x : (Bool | Int32).class)
  Output.putchar(85)
end

pick(Choice)
Output.putchar(10)
