lib LibC
  fun putchar(value : Int32) : Int32
end

class EarlierBody
  def self.value : Int32
    LaterBody.value
  end
end
class LaterBody
  def self.value : Int32
    65_i32
  end
end
LibC.putchar(EarlierBody.value)

