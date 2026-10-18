lib UnresolvedBoundaryC
  fun putchar(value : Int32) : Int32
end

class UncalledInstanceMethodOwner
  def unused_instance : Int32
    definitely_missing_instance_value(59)
  end
end

UnresolvedBoundaryC.putchar(59)
