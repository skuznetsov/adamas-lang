@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

class NamedOwner(T)
  def self.take(prefix : String = "default", payload value : T = 65, guard : Int32 = 66) forall T
    value
  end
end

def classify(value : Int32) : Int32
  65
end

def classify(value : String) : Int32
  83
end

C.putchar(classify(NamedOwner(String).take(payload: 65, guard: 66)))
