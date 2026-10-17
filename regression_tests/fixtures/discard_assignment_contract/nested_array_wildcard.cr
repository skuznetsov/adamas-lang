lib WildcardProbe
  fun putchar(value : Int32) : Int32
end

def accepts_array(value : Array(_)) : Int32
  71
end

def run
  _ = "discarded"
  WildcardProbe.putchar(accepts_array([1]))
  WildcardProbe.putchar(10)
end

run
