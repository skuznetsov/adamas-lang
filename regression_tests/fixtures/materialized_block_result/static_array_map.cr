class FirstKey
  def key : UInt64
    2_u64
  end
end

class SecondKey
  def key : UInt64
    1_u64
  end
end

items = {FirstKey.new, SecondKey.new}.to_static_array
keys = items.map { |item| item.key }
puts typeof(keys)
puts keys[0]
puts keys[1]

entries = items.map { |item| {item, item.key} }
puts typeof(entries)
puts entries[0][0].key
puts entries[0][1]
puts entries[1][0].key
puts entries[1][1]
