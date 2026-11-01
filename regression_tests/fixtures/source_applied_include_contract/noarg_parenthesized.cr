lib LibC
  fun putchar(value : Int32) : Int32
end

module AppliedNoArgResult(T)
  def selected_value : T
    @payload
  end

  def selected_inferred_value
    @payload.as(T)
  end
end

class Int64LastApplication
  @payload : Int64

  def initialize
    @payload = 64_i64
  end

  include AppliedNoArgResult(Int32)
  include AppliedNoArgResult(Int64)
end

class Int32LastApplication
  @payload : Int32

  def initialize
    @payload = 32
  end

  include AppliedNoArgResult(Int64)
  include AppliedNoArgResult(Int32)
end

def emit(value : Int32) : Int32
  if value == 32
    LibC.putchar(65)
  else
    LibC.putchar(88)
  end
end

def emit(value : Int64) : Int32
  if value == 64_i64
    LibC.putchar(66)
  else
    LibC.putchar(88)
  end
end

emit(Int64LastApplication.new.selected_value())
emit(Int32LastApplication.new.selected_value())
emit(Int64LastApplication.new.selected_inferred_value())
emit(Int32LastApplication.new.selected_inferred_value())
LibC.putchar(10)
