lib ProcCallAdmissionOutput
  fun putchar(value : Int32) : Int32
end

source = 7_i8
convert = ->(value : Int16) : Int32 { value.to_i32 }
result = convert.call(source)
ProcCallAdmissionOutput.putchar(result)
ProcCallAdmissionOutput.putchar(10_i32)
