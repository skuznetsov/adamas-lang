@[Link("gc")]
lib ReturnKindOutput
  fun putchar(value : Int32) : Int32
end

alias Int32Meta = Int32.class

def classify(value : Int32.class) : Int32
  65
end

def classify(value : Object) : Int32
  88
end

def declared_alias : Int32Meta
  Int32
end

ReturnKindOutput.putchar(classify(declared_alias))
ReturnKindOutput.putchar(10)
