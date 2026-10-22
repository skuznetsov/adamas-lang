lib ProcCallAdmissionOutput
  fun putchar(value : Int32) : Int32
end

source = 7_i16
convert = ->(value : Float32) : Int32 { value.to_i32 + 48_i32 }
result = convert.call(source)
ProcCallAdmissionOutput.putchar(result)
ProcCallAdmissionOutput.putchar(10_i32)
