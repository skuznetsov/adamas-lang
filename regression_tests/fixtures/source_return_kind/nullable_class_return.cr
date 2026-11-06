@[Link("gc")]
lib ReturnKindOutput
  fun putchar(value : Int32) : Int32
end

def classify(value : Int32.class) : Int32
  65
end

def classify(value : Nil) : Int32
  78
end

def maybe_class(condition : Bool) : (Int32.class | Nil)
  if condition
    Int32
  else
    nil
  end
end

ReturnKindOutput.putchar(classify(maybe_class(true)))
ReturnKindOutput.putchar(classify(maybe_class(false)))
ReturnKindOutput.putchar(10)
