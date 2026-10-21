lib LibC
  fun putchar(value : Int32) : Int32
end

struct Number
end
struct ReopenedChild < Number
  def marker : Int32
    65_i32
  end
end
LibC.putchar(ReopenedChild.new.marker)
