lib LibC
  fun putchar(value : Int32) : Int32
end

class ResultBox(T)
end

def collect(& : Int32, Int32 -> T) forall T
  result = ResultBox(T).new
  yield 42, 7
  result
end

def forward(& : Int32 -> U) forall U
  collect { |number| yield number }
end

def forward_again(& : Int32 -> U) forall U
  forward { |number| yield number }
end

def instance_tag(result : ResultBox(Int32))
  65
end

def class_tag(result : ResultBox(Int32.class))
  66
end

LibC.putchar(instance_tag(forward { |number| number }))
LibC.putchar(class_tag(forward_again { Int32 }))
LibC.putchar(instance_tag(forward { 9 }))
LibC.putchar(10)
