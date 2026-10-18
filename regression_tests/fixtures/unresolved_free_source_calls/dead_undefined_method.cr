lib UnresolvedBoundaryC
  fun putchar(value : Int32) : Int32
end

def unused_method_with_unresolved_call
  definitely_missing_value(59)
end

UnresolvedBoundaryC.putchar(59)
