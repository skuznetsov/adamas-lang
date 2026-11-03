# EXPECT: A
lib LibC
  fun putchar(value : Int32) : Int32
end

struct DefaultedTargetStructInstanceMember
  def value(seed : Int32 = 65_i32, *, group : Int32 = 3_i32, payload = 0_i32) : Int32
    seed
  end
end

def take_defaulted_struct(value : Int32) : Int32
  value
end

LibC.putchar(take_defaulted_struct(DefaultedTargetStructInstanceMember.new.value))
LibC.putchar(10_i32)
