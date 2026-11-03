@[Link("c")]
lib YieldContextNestedMethodLibC
  fun putchar(value : Int32) : Int32
end

def consume_block(&callback : -> Int32) : Int32
  yield
end

def forward_block(&callback : -> Int32) : Int32
  consume_block { yield }
end

if forward_block { 65 } == 65
  YieldContextNestedMethodLibC.putchar(65)
else
  YieldContextNestedMethodLibC.putchar(88)
end
YieldContextNestedMethodLibC.putchar(10)
