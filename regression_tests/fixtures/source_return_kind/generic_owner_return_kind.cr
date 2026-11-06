@[Link("gc")]
lib ReturnKindOutput
  fun putchar(value : Int32) : Int32
end

class ClassResultBox(T)
  def self.item : T
    Int32
  end
end

class InstanceResultBox(T)
  def self.item : T
    1
  end
end

def classify(value : Int32.class) : Int32
  65
end

def classify(value : Object) : Int32
  88
end

ReturnKindOutput.putchar(classify(ClassResultBox(Int32.class).item))
ReturnKindOutput.putchar(classify(InstanceResultBox(Int32).item))
ReturnKindOutput.putchar(10)
