lib LibC
  fun putchar(value : Int32) : Int32
end

class SuperTupleBase
  alias Result = Int32

  def self.pack(value : Result) : Tuple(self, Result)
    {new, value}
  end
end

class SuperTupleChild < SuperTupleBase
  alias Result = String

  def self.pack(value : Int32) : Tuple(self, SuperTupleBase::Result)
    super(value)
  end
end

def mark(value : SuperTupleChild) : Int32
  65
end

def mark(value : SuperTupleBase) : Int32
  66
end

pair = SuperTupleChild.pack(65)
LibC.putchar(mark(pair[0]))
LibC.putchar(pair[1])
LibC.putchar(10)
