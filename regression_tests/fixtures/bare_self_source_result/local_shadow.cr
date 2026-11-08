lib Output
  fun putchar(value : Int32) : Int32
end

class BareSelfLocalShadowProbe
  def value
    65
  end

  def run
    value = 66
    value
  end
end

Output.putchar(BareSelfLocalShadowProbe.new.run)
Output.putchar(10)
