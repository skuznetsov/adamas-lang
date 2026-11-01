abstract struct Enum
  def value : Int
    previous_def
  end

  def includes?(other : self) : Bool
    (value & other.value) == other.value
  end
end

@[::Flags]
enum KnownFlag : Int16
  Present = 1
end

def unknown_predicate(value : KnownFlag) : Bool
  value.not_declared?
end

unknown_predicate(KnownFlag::Present)
