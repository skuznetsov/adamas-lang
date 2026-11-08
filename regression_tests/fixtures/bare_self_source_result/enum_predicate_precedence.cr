lib Output
  fun putchar(value : Int32) : Int32
end

# Minimal Enum methods used by Crystal's generated member predicates. These
# mirror Enum#value and Enum#==(other : self) from the installed enum.cr.
abstract struct Enum
  def value : Int32
    previous_def
  end

  def ==(other : self) : Bool
    value == other.value
  end
end

enum BareSelfState
  Ready
  Waiting

  def ready_from_self?
    ready?
  end
end

Output.putchar(BareSelfState::Ready.ready_from_self? ? 65 : 66)
Output.putchar(BareSelfState::Waiting.ready_from_self? ? 65 : 66)
Output.putchar(10)
