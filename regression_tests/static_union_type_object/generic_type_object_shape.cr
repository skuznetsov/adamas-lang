@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

alias Choice = Bool | Int32

def union_value(flag : Bool) : Bool | Int32
  flag ? false : 7
end

def accept_type_object(value : T.class) forall T
  Output.putchar(65)
end

def accept_value(value : T) forall T
  Output.putchar(71)
end

accept_type_object(Choice)
accept_type_object(typeof(union_value(true)))
accept_type_object(Bool)
accept_type_object(Int32)
accept_value(true)
accept_value(7)
Output.putchar(10)
