lib UnresolvedBoundaryC
  fun putchar(value : Int32) : Int32
end

def unused_typed_free : Int32
  definitely_missing_typed_free_value(59)
end

UnresolvedBoundaryC.putchar(59)
