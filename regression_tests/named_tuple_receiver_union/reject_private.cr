struct NamedTuple
  private def hidden(code : Int32)
    code
  end
end

def row(flag : Bool)
  flag ? {value: 1} : {other: 2_i64}
end

row(true).hidden(1)
