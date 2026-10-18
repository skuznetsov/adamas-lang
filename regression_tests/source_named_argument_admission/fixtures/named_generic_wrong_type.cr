def accept(*, value : Tuple(Int32, Int32))
  value
end

accept(value: {1, "wrong"})
