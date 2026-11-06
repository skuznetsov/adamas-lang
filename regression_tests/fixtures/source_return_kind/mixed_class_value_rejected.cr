@[Link("gc")]
lib ReturnKindOutput
 fun putchar(value : Int32) : Int32
end
def tag(value : Int32.class) : Int32
 65
end
def tag(value : Int32) : Int32
 88
end
def mixed(value : T, condition : Bool) : T forall T
 if condition
  value
 else
  1
 end
end
ReturnKindOutput.putchar(tag(mixed(Int32, true)))
