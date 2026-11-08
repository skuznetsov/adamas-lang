lib LibC
  fun putchar(value : Int32) : Int32
end

def pick(value : Int32) : Int32
  65
end

def pick(value : Nil) : Int32
  66
end

class R
  def initialize(value : Int32)
    65
  end

  def run
    initialize(1)
  end
end

LibC.putchar(pick(R.new(0).run))
LibC.putchar(10)
