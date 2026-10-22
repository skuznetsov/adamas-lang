lib ProcCallAdmissionOutput
  fun putchar(value : Int32) : Int32
end

convert = ->(value : Int8) : Int32 { value.to_i32 + 49_i32 }
result = convert.call(-1)
ProcCallAdmissionOutput.putchar(result)
ProcCallAdmissionOutput.putchar(10_i32)
