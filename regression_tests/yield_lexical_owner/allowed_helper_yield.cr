@[Link("c")]
lib YieldLexicalOwnerAllowedLibC
  fun putchar(value : Int32) : Int32
end

def helper(&callback : -> Int32) : Int32
  yield
end

saved = -> { helper { 65 } }
if saved.call == 65
  YieldLexicalOwnerAllowedLibC.putchar(65)
else
  YieldLexicalOwnerAllowedLibC.putchar(88)
end
YieldLexicalOwnerAllowedLibC.putchar(10)
