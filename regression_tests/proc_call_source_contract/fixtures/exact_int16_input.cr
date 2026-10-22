lib ProcCallAdmissionOutput
  fun putchar(value : Int32) : Int32
end
convert = ->(value : Int16) : Int32 { value == 65_i16 ? 65_i32 : 66_i32 }
source = 65_i16
ProcCallAdmissionOutput.putchar(convert.call(source))
ProcCallAdmissionOutput.putchar(10_i32)
