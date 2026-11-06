@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
  fun rand : Int32
end

def deferred_nil(flag : Bool, &block : -> T) : T forall T
  if flag
    return 65
  else
    yield
  end
end

def classify(value : Nil) : Int32
  65
end

def classify(value : Object) : Int32
  73
end

flag = C.rand == 0
C.putchar(classify(deferred_nil(flag) { nil }))
C.putchar(classify(deferred_nil(!flag) { nil }))
C.putchar(10)
