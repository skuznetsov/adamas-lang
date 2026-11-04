struct NamedTuple
  def select(value : self)
    value
  end
end

def row(flag : Bool)
  flag ? {value: 1} : {other: 2_i64}
end

row(true).select({value: 2})
