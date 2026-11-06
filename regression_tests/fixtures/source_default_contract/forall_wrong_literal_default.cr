@[Link("c")]
lib C
 fun putchar(value : Int32) : Int32
 fun exit(status : Int32) : NoReturn
end
class Token
end
def take(value : T, fallback : T = 65) forall T
 fallback
end
take(Token.new)
