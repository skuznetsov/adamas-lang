@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

def selected_value(flag : Bool) : Bool | Int32
  flag ? false : 7
end

def accept_type_object(value : T.class) forall T
  Output.putchar(65)
end

accept_type_object(selected_value(true))
Output.putchar(10)
