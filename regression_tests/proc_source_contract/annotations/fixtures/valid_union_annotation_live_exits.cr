require "proc"
lib ProcAnnotationOutput
  fun putchar(value : Int32) : Int32
end
def choose_other_exit : Bool
  false
end
value = -> : (Int32 | String) {
  if choose_other_exit
    "alternate"
  else
    7_i32
  end
}
value.call
ProcAnnotationOutput.putchar(85_i32)
ProcAnnotationOutput.putchar(10_i32)
