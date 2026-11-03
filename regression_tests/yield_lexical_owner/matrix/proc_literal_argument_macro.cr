macro yield_argument_marker
  {% raise "yield argument expansion marker" %}
  0
end

def capture_yield_proc(&callback : -> Int32)
  -> { yield yield_argument_marker }
end

capture_yield_proc { 65 }
