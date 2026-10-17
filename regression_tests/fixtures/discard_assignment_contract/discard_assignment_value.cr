lib WildcardProbe
  fun putchar(value : Int32) : Int32
end

def run
  value = (_ = 65)
  WildcardProbe.putchar(value)
  WildcardProbe.putchar(10)
end

run
