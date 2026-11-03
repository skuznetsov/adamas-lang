lib LibC
  fun putchar(value : Int32) : Int32
end
class DefaultedTargetInstanceMember
  def value(seed : Int32 = 65_i32, *, group : Int32 = 3_i32, payload = 0_i32) : Int32
    seed
  end

  def self.take(value : Int) : Int32
    65_i32
  end
end
owner = DefaultedTargetInstanceMember.new
LibC.putchar(DefaultedTargetInstanceMember.take(owner.value))
LibC.putchar(10_i32)
