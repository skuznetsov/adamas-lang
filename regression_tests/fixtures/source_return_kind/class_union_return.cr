class ReturnKindString
end

@[Link("gc")]
lib ReturnKindOutput
  fun putchar(value : Int32) : Int32
end

alias ClassChoice = Int32.class | ReturnKindString.class

def classify(value : Int32.class) : Int32
  73
end

def classify(value : ReturnKindString.class) : Int32
  83
end

def declared_choice(condition : Bool) : ClassChoice
  if condition
    Int32
  else
    ReturnKindString
  end
end

ReturnKindOutput.putchar(classify(declared_choice(true)))
ReturnKindOutput.putchar(classify(declared_choice(false)))
ReturnKindOutput.putchar(10)
