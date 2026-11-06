@[Link("c")]
lib C
 fun putchar(value : Int32) : Int32
end
class G(T)
 def self.take(x : T, fallback : T = x) forall T
 fallback
 end
end
C.putchar(G(String).take(x: 65))
