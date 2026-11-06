@[Link("c")]
lib DefaultNumericC
  fun putchar(value : Int32) : Int32
end

def choose(value : Float64 = 65)
  value
end

if choose() == 65.0
  DefaultNumericC.putchar(65)
else
  DefaultNumericC.putchar(66)
end
DefaultNumericC.putchar(10)
