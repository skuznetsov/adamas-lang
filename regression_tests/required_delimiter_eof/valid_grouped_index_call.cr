lib RequiredDelimiterOracle
  fun putchar(value : Int32) : Int32
end

class RequiredDelimiterIndex
  def self.[](index : Int32) : Int32
    66_i32
  end
end

RequiredDelimiterOracle.putchar(RequiredDelimiterIndex[(0_i32)])
