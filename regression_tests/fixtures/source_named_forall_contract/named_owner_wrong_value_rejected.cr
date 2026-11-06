@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

class NamedOwner(T)
  def self.take(x : T, guard : Int32) forall T
    x
  end
end

NamedOwner(String).take(x: 65, guard: "bad")
