lib ProcCallAdmissionOutput
  fun putchar(value : Int32) : Int32
end
convert = ->(value : Float32) : Int32 { value == 65.0_f32 ? 65_i32 : 66_i32 }
source = 65.0_f32
ProcCallAdmissionOutput.putchar(convert.call(source))
ProcCallAdmissionOutput.putchar(10_i32)
