struct FloatSlot(T)
  def put(value : T) : T
    value
  end
end

value = 0_i64
FloatSlot(Float64).new.put(value)
