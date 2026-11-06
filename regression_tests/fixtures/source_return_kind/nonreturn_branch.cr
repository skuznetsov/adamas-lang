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
def branch(value : T, condition : Bool) : T forall T
 if condition
  value
 else
  value
 end
end
ReturnKindOutput.putchar(tag(branch(Int32, false)))
ReturnKindOutput.putchar(10)
