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

1_u64.value_self_contract(65_u64, 66_u64)
