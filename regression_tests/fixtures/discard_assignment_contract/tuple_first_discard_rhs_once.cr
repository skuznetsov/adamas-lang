lib WildcardProbe
  fun putchar(value : Int32) : Int32
end

def make_pair
  WildcardProbe.putchar(67)
  {68, 69}
end

def run
  _, keep = make_pair
  WildcardProbe.putchar(keep)
  WildcardProbe.putchar(10)
end

run
