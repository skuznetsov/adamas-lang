@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

module NamedKindDispatch
  def choose(type_value : T.class, instance_value : T) forall T
    65
  end

  def choose(type_value : Class, instance_value : Object)
    73
  end
end

class NamedKindOwner
  extend NamedKindDispatch
end

C.putchar(NamedKindOwner.choose(instance_value: 65, type_value: Int32))
