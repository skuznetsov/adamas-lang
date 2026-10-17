lib WildcardProbe
  fun putchar(value : Int32) : Int32
end

def condition_once : Int32
  WildcardProbe.putchar(65)
  1
end

def run
  if _ = condition_once
    WildcardProbe.putchar(66)
  end
  WildcardProbe.putchar(10)
end

run
