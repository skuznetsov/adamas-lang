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
enum SourcePermissions : Int16
  Read = 1
  Write = 2
end

def flags_all_question(value : SourcePermissions) : Bool
  value.all?
end

flags_all_question(SourcePermissions::All)
