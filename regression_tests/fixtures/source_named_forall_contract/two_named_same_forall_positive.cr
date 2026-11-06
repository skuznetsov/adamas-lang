@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

class NamedOwner(T)
  def self.pair(left : T, right : T) forall T
    left
  end
end

def classify(value : Int32) : Int32
  65
end

def classify(value : String) : Int32
  83
end

C.putchar(classify(NamedOwner(String).pair(right: 66, left: 65)))
