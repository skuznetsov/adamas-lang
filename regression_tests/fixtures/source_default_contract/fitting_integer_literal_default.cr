@[Link("c")]
lib DefaultNumericC
  fun putchar(value : Int32) : Int32
end

def choose(value : Int8 = 65)
  value
end

DefaultNumericC.putchar(choose().to_i32)
DefaultNumericC.putchar(10)
