lib ProcCallAdmissionOutput
  fun putchar(value : Int32) : Int32
end

convert = ->(value : Int8) : Int32 { value.to_i32 }
result = convert.call(127)
ProcCallAdmissionOutput.putchar(result)
ProcCallAdmissionOutput.putchar(10_i32)
