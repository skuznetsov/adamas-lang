@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

class NamedOwner(T)
  def self.take(x : T, fallback : T = x) forall T
    fallback
  end
end

def classify(value : Int32) : Int32
  65
end

def classify(value : String) : Int32
  83
end

C.putchar(classify(NamedOwner(String).take(x: 65)))
