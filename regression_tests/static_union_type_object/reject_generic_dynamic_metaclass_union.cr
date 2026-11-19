@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

def selected_type(flag : Bool) : Bool.class | Int32.class
  flag ? Bool : Int32
end

def accept_type_object(value : T.class) forall T
  Output.putchar(65)
end

accept_type_object(selected_type(true))
Output.putchar(10)
