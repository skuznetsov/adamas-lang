@[Link("c")]
lib YieldContextEffectLibC
  fun putchar(value : Int32) : Int32
end

def capture_yield_proc(&callback : -> Int32)
  -> { yield YieldContextEffectLibC.putchar(88) + missing_yield_argument }
end

capture_yield_proc { 65 }
