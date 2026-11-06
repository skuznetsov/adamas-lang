@[Link("c")]
lib C
 fun putchar(value : Int32) : Int32
 fun exit(status : Int32) : NoReturn
end
def take(value : T, fallback : T = 66) forall T
 fallback
end
C.putchar(take(1_i64) == 66_i64 ? 65 : 66)
C.putchar(10)
