@[Link("c")]
lib YieldLexicalUnusedBlockLibC
  fun putchar(value : Int32) : Int32
end

def use_typed_but_unused_block(&callback : -> Int32) : Int32
  yield
end

if use_typed_but_unused_block { 65 } == 65
  YieldLexicalUnusedBlockLibC.putchar(65)
else
  YieldLexicalUnusedBlockLibC.putchar(88)
end
YieldLexicalUnusedBlockLibC.putchar(10)
