lib UnresolvedBoundaryC
  fun putchar(value : Int32) : Int32
end

class UncalledClassMethodOwner
  def self.unused_class : Int32
    definitely_missing_class_value(59)
  end
end

UnresolvedBoundaryC.putchar(59)
