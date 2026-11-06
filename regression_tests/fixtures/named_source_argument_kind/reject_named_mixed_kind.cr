@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
def condition : Bool
  true
end
def only_class(value : Int32.class) : Int32
  65
end
value = if condition
  Int32
else
  1
end
C.putchar(only_class(value: value))
