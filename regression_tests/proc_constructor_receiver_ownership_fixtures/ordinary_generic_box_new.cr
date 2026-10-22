lib ProcConstructorFactOutput
  fun putchar(value : Int32) : Int32
end

class ProcConstructorFactBox(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end

box = ProcConstructorFactBox(Int32).new(65_i32)
ProcConstructorFactOutput.putchar(box.value)
ProcConstructorFactOutput.putchar(10_i32)
