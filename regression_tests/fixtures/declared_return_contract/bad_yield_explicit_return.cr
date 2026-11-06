@[Link("gc")]

def result(flag : Bool) : Bool
  if flag
    return 65
  end
  yield
  true
end

result(false) { nil }
