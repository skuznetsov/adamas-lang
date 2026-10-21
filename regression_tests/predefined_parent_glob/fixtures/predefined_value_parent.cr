lib LibC
  fun putchar(value : Int32) : Int32
end

struct PredefinedChild < Value
  def marker : Int32
    65_i32
  end
end
LibC.putchar(PredefinedChild.new.marker)
