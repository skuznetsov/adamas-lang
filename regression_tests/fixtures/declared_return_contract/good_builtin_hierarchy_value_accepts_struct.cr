@[Link("c")]
lib C
 fun putchar(value : Int32) : Int32
end

class Context(T)
 def initialize(@marker : T)
 end
end

struct Token
end

module Action(T)
 def step0(marker)
  value = Token.new
  keep(value)
  value
 end
 def keep(value) : Nil
 end
 def step1(marker)
  step0(marker)
 end
 def step2(marker)
  step1(marker)
 end
 def step3(marker)
  step2(marker)
 end
 def step4(marker)
  step3(marker)
 end
 def step5(marker) : Value
  return step4(marker)
 end
 def step6(marker)
  step5(marker)
 end
 def step7(marker)
  step6(marker)
 end
 def step8(marker)
  step7(marker)
 end
end

class Receiver(T)
 include Action(T)
end

Receiver(Int32).new.step8(65)
C.putchar(65)
C.putchar(10)
