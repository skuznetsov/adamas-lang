class SelectedGenericNilableValues(T)
  def initialize(@value : T)
  end

  def values(index : Int32) : Array(T)
    [@value]
  end

  def values : Array(T?)
    [@value, nil]
  end
end

receiver = SelectedGenericNilableValues(String).new("present")
zero_arg = receiver.values
indexed_values = receiver.values(0)
puts zero_arg.size
puts zero_arg[1].nil?
puts indexed_values.size
puts indexed_values[0]
