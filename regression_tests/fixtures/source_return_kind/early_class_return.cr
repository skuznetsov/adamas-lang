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
def early(value : T, condition : Bool) : T forall T
 return value if condition
 value
end
ReturnKindOutput.putchar(tag(early(Int32, true)))
ReturnKindOutput.putchar(10)
