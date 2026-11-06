class NamedOwner(T)
  def self.take(prefix : String = "default", payload value : T = 65, guard : Int32 = 66) forall T
    value
  end
end

NamedOwner(String).take(payload: 65, guard: "bad")
