lib WildcardProbe
  fun putchar(value : Int32) : Int32
end

def make_pair
  WildcardProbe.putchar(67)
  {68, 69}
end

def run
  first, _ = make_pair
  WildcardProbe.putchar(first)
  WildcardProbe.putchar(10)
end

run
