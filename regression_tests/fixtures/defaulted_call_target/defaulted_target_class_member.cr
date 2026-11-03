lib LibC
  fun putchar(value : Int32) : Int32
end
class DefaultedTargetClassMember
  def self.value(seed : Int32 = 65_i32, *, group : Int32 = 3_i32, payload = 0_i32) : Int32
    seed
  end

  def self.take(value : Int) : Int32
    65_i32
  end
end
LibC.putchar(DefaultedTargetClassMember.take(DefaultedTargetClassMember.value))
LibC.putchar(10_i32)
