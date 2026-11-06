@[Link("c")]
lib C
 fun putchar(value : Int32) : Int32
end
class G(T)
 def self.take(x : T = 65) forall T
 x
 end
end
C.putchar(G(String).take)
