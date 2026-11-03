def helper(&callback : -> Int32) : Int32
  yield
end

def capture_yield_proc(&callback : -> Int32) : Int32
  saved = -> { helper { yield } }
  saved.call
end

capture_yield_proc { 65 }
