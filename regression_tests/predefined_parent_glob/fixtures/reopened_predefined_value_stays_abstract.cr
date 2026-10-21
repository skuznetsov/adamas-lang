lib LibC
  fun putchar(value : Int32) : Int32
end

struct Value
end
struct ReopenedChild < Value
  def marker : Int32
    65_i32
  end
end
LibC.putchar(ReopenedChild.new.marker)
