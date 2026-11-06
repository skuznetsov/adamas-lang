@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

def nil_union_return_if_yield(&block : -> T) : Int32 | T forall T
  return 65 if yield
  yield
end

def classify(value : Nil) : Int32
  65
end

def classify(value : Int32) : Int32
  73
end

def classify(value : Bool) : Int32
  66
end

def classify(value : Object) : Int32
  88
end

C.putchar(classify(nil_union_return_if_yield { true }))
C.putchar(classify(nil_union_return_if_yield { nil }))
C.putchar(10)
