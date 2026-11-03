macro emit_yield
  {{ "yield".id }}
end

def capture_yield_proc(&callback : -> Int32)
  -> { emit_yield }
end

capture_yield_proc { 65 }
