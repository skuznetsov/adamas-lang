lib ClassIvarMatrixC
  fun putchar(value : Int32) : Int32
end

macro install_class_defaults(zero, nonzero, enabled, wide, owner_code)
  @zero_value = {{zero}}
  @nonzero_value = {{nonzero}}
  @enabled = {{enabled}}
  @wide_value = {{wide}}
  @owner_code = {{owner_code}}

  def zero_value
    @zero_value
  end

  def nonzero_value
    @nonzero_value
  end

  def enabled
    @enabled
  end

  def wide_value
    @wide_value
  end

  def owner_code
    @owner_code
  end
end

class FirstGeneratedOwner
  @wide_value : Int64
  install_class_defaults(0, 7, false, 9_i64, 3)
end

class SecondGeneratedOwner
  @wide_value : Int64
  install_class_defaults(2, 4, true, 12_i64, 8)
end

def int32_digit(value : Int32) : Int32
  value | 48
end

def bool_digit(value : Bool) : Int32
  value ? 49 : 48
end

def int64_matches(value : Int64, expected : Int64) : Int32
  value == expected ? 49 : 48
end

first = FirstGeneratedOwner.new
second = SecondGeneratedOwner.new
ClassIvarMatrixC.putchar(int32_digit(first.zero_value))
ClassIvarMatrixC.putchar(int32_digit(first.nonzero_value))
ClassIvarMatrixC.putchar(bool_digit(first.enabled))
ClassIvarMatrixC.putchar(int64_matches(first.wide_value, 9_i64))
ClassIvarMatrixC.putchar(int32_digit(first.owner_code))
ClassIvarMatrixC.putchar(int32_digit(second.zero_value))
ClassIvarMatrixC.putchar(int32_digit(second.nonzero_value))
ClassIvarMatrixC.putchar(bool_digit(second.enabled))
ClassIvarMatrixC.putchar(int64_matches(second.wide_value, 12_i64))
ClassIvarMatrixC.putchar(int32_digit(second.owner_code))
ClassIvarMatrixC.putchar(10)
