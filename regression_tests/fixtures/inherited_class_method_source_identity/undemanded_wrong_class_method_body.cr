lib LibC
  fun putchar(c : Int32) : Int32
end

class UndemandedWrongMethodBase
  def self.parse(value : String) : Int32
    65
  end
end

class UndemandedWrongMethodChild < UndemandedWrongMethodBase
  def self.unused : Int32
    UndemandedWrongMethodChild.parse(1)
  end
end

# Crystal normally type-checks a method body on demand. Keep `unused` dead so
# the overload guard is tested at an actual demanded call boundary only.
LibC.putchar(85)
LibC.putchar(10)
