@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

def selected(flag : Bool) : Bool.class | Int32.class
  flag ? Bool : Int32
end

def accept(value : Bool.class | Int32.class)
  Output.putchar(86)
end

accept(selected(true))
accept(selected(false))
Output.putchar(10)
