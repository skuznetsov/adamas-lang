@[Link("gc")]
lib ReturnKindOutput
  fun putchar(value : Int32) : Int32
end

def classify(value : Class) : Int32
  65
end

def classify(value : Object) : Int32
  88
end

def declared_class : Class
  Int32
end

ReturnKindOutput.putchar(classify(declared_class))
ReturnKindOutput.putchar(10)
