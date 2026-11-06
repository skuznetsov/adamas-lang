class ReturnKindString
end

@[Link("gc")]
lib ReturnKindOutput
  fun putchar(value : Int32) : Int32
end

def classify(value : Int32.class) : Int32
  73
end

def classify(value : ReturnKindString.class) : Int32
  83
end

def classify(value : Int32) : Int32
  88
end

def classify(value : ReturnKindString) : Int32
  89
end

def identity(value : T) : T forall T
  value
end

ReturnKindOutput.putchar(classify(identity(Int32)))
ReturnKindOutput.putchar(classify(identity(ReturnKindString)))
ReturnKindOutput.putchar(10)
