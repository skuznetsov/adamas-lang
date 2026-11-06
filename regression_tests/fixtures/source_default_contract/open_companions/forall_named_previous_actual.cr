@[Link("c")]
lib C
 fun putchar(value : Int32) : Int32
 fun exit(status : Int32) : NoReturn
end
def take(value : T, fallback : T = value) forall T
 fallback
end
C.putchar(take(value: 65))
C.putchar(10)
