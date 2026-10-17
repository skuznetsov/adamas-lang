lib WildcardProbe
  fun putchar(value : Int32) : Int32
end

def identity(value : _) : UInt32
  value
end

def run
  _ = "discarded"
  value = identity(65_u32)
  WildcardProbe.putchar(value.to_i)
  WildcardProbe.putchar(10)
end

run
