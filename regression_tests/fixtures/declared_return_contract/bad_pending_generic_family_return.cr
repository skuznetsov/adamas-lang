# Completing a source result must still enforce its declared restriction.
@[Link("c")]
lib C
 fun putchar(value : Int32) : Int32
end
class Context(T)
 def initialize(@marker : T)
 end
 def marker
  @marker
 end
end
module Action(T)
 def step0(marker)
  context = Context(T).new(marker)
  keep(context)
  context
 end
 def keep(value : Context(T)) : Nil
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
 def step5(marker) : Context
  return "bad"
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
C.putchar(Receiver(Int32).new.step8(65).marker)
C.putchar(10)
