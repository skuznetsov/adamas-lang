lib LibC
  fun exit(status : Int32) : NoReturn
end

struct BoundaryValue
  def initialize(@value : Int32)
  end

  def value
    @value
  end

  def apply(&)
    yield self
  end
end

def bare_apply(&)
  yield BoundaryValue.new(42)
end

def details
  {
    value: BoundaryValue.new(42).apply &.value,
    after: 7,
  }
end

def trailing_details
  {value: BoundaryValue.new(42).apply &.value,}
end

def bare_details
  {value: bare_apply &.value, after: 7}
end

a = details
LibC.exit(1) unless a[:value] == 42 && a[:after] == 7
b = trailing_details
LibC.exit(2) unless b[:value] == 42
c = bare_details
LibC.exit(3) unless c[:value] == 42 && c[:after] == 7
LibC.exit(0)
