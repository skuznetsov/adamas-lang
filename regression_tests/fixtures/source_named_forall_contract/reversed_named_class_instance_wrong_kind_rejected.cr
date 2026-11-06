module NamedKindDispatch
  def choose(type_value : T.class, instance_value : T) forall T
    65
  end
end

class NamedKindOwner
  extend NamedKindDispatch
end

NamedKindOwner.choose(instance_value: "bad", type_value: Int32)
