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
def other(value : T, result : U) : U forall T, U
 result
end
ReturnKindOutput.putchar(tag(other(Int32, 1)))
ReturnKindOutput.putchar(10)
