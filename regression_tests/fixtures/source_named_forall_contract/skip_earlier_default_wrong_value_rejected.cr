class NamedOwner(T)
  def self.take(prefix : String = "default", x : T = 65, guard : Int32 = 66) forall T
    x
  end
end

NamedOwner(String).take(x: 65, guard: "bad")
