lib StructIvarMatrixC
  fun putchar(value : Int32) : Int32
end

macro install_struct_defaults(nonzero, enabled)
  @zero_value = 0
  @nonzero_value = {{nonzero}}
  @enabled = {{enabled}}

  def zero_value
    @zero_value
  end

  def nonzero_value
    @nonzero_value
  end

  def enabled
    @enabled
  end
end

struct GeneratedStructOwner
  install_struct_defaults(5, false)
end

def struct_int32_digit(value : Int32) : Int32
  value | 48
end

def struct_bool_digit(value : Bool) : Int32
  value ? 49 : 48
end

record = GeneratedStructOwner.new
StructIvarMatrixC.putchar(struct_int32_digit(record.zero_value))
StructIvarMatrixC.putchar(struct_int32_digit(record.nonzero_value))
StructIvarMatrixC.putchar(struct_bool_digit(record.enabled))
StructIvarMatrixC.putchar(10)
