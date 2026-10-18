lib UnresolvedBoundaryC
  fun putchar(value : Int32) : Int32
end

UnresolvedBoundaryC.putchar(delayed_value(59))

def delayed_value(input : Int32) : Int32
  input
end
