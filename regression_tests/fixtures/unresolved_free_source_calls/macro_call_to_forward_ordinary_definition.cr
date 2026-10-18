lib UnresolvedBoundaryC
  fun putchar(value : Int32) : Int32
end

macro invoke_delayed_value
  delayed_value(59)
end

UnresolvedBoundaryC.putchar(invoke_delayed_value)

def delayed_value(input : Int32) : Int32
  input
end
