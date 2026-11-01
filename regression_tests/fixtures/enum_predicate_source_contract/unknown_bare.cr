abstract struct Enum
  def value : Int
    previous_def
  end

  def ==(other : self) : Bool
    value == other.value
  end

  def includes?(other : self) : Bool
    (value & other.value) == other.value
  end
end

@[::Flags]
enum UnknownBareFlags : Int16
  Present = 1

  def probe : Bool
    not_declared?
  end
end

UnknownBareFlags.new(1_i16).probe
