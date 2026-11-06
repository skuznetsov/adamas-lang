@[Link("gc")]
lib ReturnKindOutput
  fun putchar(value : Int32) : Int32
end

def classify(value : Int32.class) : Int32
  65
end

def classify(value : Int32) : Int32
  88
end

def identity(value : T) forall T
  value
end

ReturnKindOutput.putchar(classify(identity(Int32)))
ReturnKindOutput.putchar(classify(identity(1)))
ReturnKindOutput.putchar(10)
