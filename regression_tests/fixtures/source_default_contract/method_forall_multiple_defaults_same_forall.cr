@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

class G(T)
  def self.take(first : T = 65, second : T = first) forall T
    second
  end
end

C.putchar(G(String).take)
