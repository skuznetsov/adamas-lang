def capture_yield_proc(&callback : -> Int32)
  -> { yield }
end

capture_yield_proc { 65 }
