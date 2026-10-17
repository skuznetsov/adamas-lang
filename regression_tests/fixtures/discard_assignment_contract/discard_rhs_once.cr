lib WildcardProbe
  fun putchar(value : Int32) : Int32
end

def rhs_once : Int32
  WildcardProbe.putchar(65)
  66
end

def run
  _ = rhs_once
  WildcardProbe.putchar(66)
  WildcardProbe.putchar(10)
end

run
