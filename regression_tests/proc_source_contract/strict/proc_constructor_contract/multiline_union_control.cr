lib ProcContractRuntime
  fun putchar(value : Int32) : Int32
end
alias MultilineValue = Int32 |
                       Bool
value : MultilineValue = true
if value.is_a?(Bool)
  ProcContractRuntime.putchar(85_i32)
else
  ProcContractRuntime.putchar(88_i32)
end
ProcContractRuntime.putchar(10_i32)
