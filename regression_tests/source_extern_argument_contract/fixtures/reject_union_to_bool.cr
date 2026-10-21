lib C
  fun accept(value : Bool) : Bool
end
def value(flag : Bool) : Bool | String
  flag ? true : "bad"
end
C.accept(value(true))
