@[Link("c")]
lib C
 fun putchar(value : Int32) : Int32
 fun exit(status : Int32) : NoReturn
end
def take(value : T = 65, &block : -> T) forall T
 value
end
C.putchar(take { 66 })
C.putchar(10)
