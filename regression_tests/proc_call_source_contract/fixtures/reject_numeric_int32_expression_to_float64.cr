lib ProcCallAdmissionOutput
  fun putchar(value : Int32) : Int32
end

source = 7_i32
convert = ->(value : Float64) : Int32 { value.to_i32 + 48_i32 }
result = convert.call(source)
ProcCallAdmissionOutput.putchar(result)
ProcCallAdmissionOutput.putchar(10_i32)
