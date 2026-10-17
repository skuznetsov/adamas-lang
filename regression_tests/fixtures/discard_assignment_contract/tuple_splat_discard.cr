lib WildcardProbe
  fun putchar(value : Int32) : Int32
end

def run
  first, *_, last = {70, 71, 72, 73}
  WildcardProbe.putchar(first)
  WildcardProbe.putchar(last)
  WildcardProbe.putchar(10)
end

run
