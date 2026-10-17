lib WildcardProbe
  fun putchar(value : Int32) : Int32
end

def run
  _ = "discarded"
  WildcardProbe.putchar(_)
end

run
