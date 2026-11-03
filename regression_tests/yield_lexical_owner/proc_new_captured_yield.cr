def capture_proc_new_yield(&callback : -> Int32) : Proc(Int32)
  Proc(Int32).new { yield }
end

capture_proc_new_yield { 65 }
