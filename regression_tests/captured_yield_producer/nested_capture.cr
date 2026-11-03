@[Link("c")]
lib FallbackScopeNestedLibC
  fun putchar(value : Int32) : Int32
end

def fallback_scope_value(&block : -> Int32) : Int32
  yield
end

def fallback_scope_outer(&block : -> Int32) : Int32
  fallback_scope_value { yield }
end

captured = 66
result = fallback_scope_outer do
  captured = 65
  captured
end
if result == 65 && captured == 65
  FallbackScopeNestedLibC.putchar(65)
else
  FallbackScopeNestedLibC.putchar(88)
end
FallbackScopeNestedLibC.putchar(10)
