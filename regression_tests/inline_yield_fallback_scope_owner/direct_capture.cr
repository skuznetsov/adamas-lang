@[Link("c")]
lib FallbackScopeDirectLibC
  fun putchar(value : Int32) : Int32
end

def fallback_scope_value(&block : -> Int32) : Int32
  yield
end

captured = 66
fallback_scope_value { captured = 65 }
if captured == 65
  FallbackScopeDirectLibC.putchar(65)
else
  FallbackScopeDirectLibC.putchar(88)
end
FallbackScopeDirectLibC.putchar(10)
