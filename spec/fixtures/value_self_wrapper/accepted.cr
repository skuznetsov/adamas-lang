lib ValueSelfContractC
  fun putchar(value : Int32) : Int32
end

class Object
  def value_self_contract : UInt64
    value_self_contract(65_u64)
  end
end

struct Value
end

struct Number
end

struct Int
end

struct UInt64
  def value_self_contract(item)
    item
  end
end

if 1_u64.value_self_contract == 65_u64
  ValueSelfContractC.putchar(65)
else
  ValueSelfContractC.putchar(66)
end
ValueSelfContractC.putchar(10)
